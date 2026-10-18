#!/usr/bin/env python3
"""
Uji otomatis M1 (database Code2Ticket) pada Postgres lokal.

Menjalankan: skema + fungsi pada database baru, lalu menguji alur auth, input kode,
draw commit-reveal, hash-chain (dengan implementasi verifikasi Python TERPISAH yang
mengikuti kontrak di db/README.md), hak akses role anon, dan konkurensi.

  PGHOST=/tmp PGPORT=54329 PGUSER=postgres python3 db/tests/test_m1.py
"""
import concurrent.futures as cf
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
from decimal import Decimal

import psycopg

HERE = os.path.dirname(os.path.abspath(__file__))
DBDIR = os.path.dirname(HERE)
HOST = os.environ.get("PGHOST", "/tmp")
PORT = os.environ.get("PGPORT", "54329")
USER = os.environ.get("PGUSER", "postgres")
DBNAME = "c2t_test"
PBKDF2_ITER = 10_000

passed, failed = 0, []


def check(name, cond, detail=""):
    global passed
    if cond:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed.append(name)
        print(f"  FAIL {name}  {detail}")


def section(title):
    print(f"\n== {title}")


# ---------------------------------------------------------------- koneksi
def conninfo(db):
    return f"host={HOST} port={PORT} user={USER} dbname={db}"


def superuser():
    return psycopg.connect(conninfo(DBNAME), autocommit=True)


def anon():
    c = psycopg.connect(conninfo(DBNAME), autocommit=True)
    c.execute("set role anon")
    return c


def one(conn, sql, params=()):
    row = conn.execute(sql, params).fetchone()
    return row[0] if row else None


def rpc(conn, fn, *args, casts=None):
    casts = casts or [""] * len(args)
    ph = ", ".join(f"%s{c}" for c in casts)
    return one(conn, f"select public.{fn}({ph})", args)


def sqlstate_of(fn):
    try:
        fn()
    except psycopg.Error as e:
        return e.sqlstate
    return None


# ---------------------------------------------------------------- kontrak klien (Dart harus identik)
def client_hash(password, salt):
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ITER, 32).hex()


def register(conn, username, email, password, name="Tester"):
    salt = os.urandom(16).hex()
    return rpc(conn, "rpc_register", username, email, name, salt, client_hash(password, salt))


def login(conn, ident, password):
    salt = rpc(conn, "rpc_get_salt", ident)["salt"]
    return rpc(conn, "rpc_login", ident, client_hash(password, salt))


def sha(s):
    return hashlib.sha256(s.encode()).hexdigest()


def block_hash(b):
    if b["block_type"] == "commit":
        s = f"C|{b['block_index']}|{b['giveaway_id']}|{b['seed_hash']}|{b['winner_count']}|{b['ts_ms']}|{b['previous_hash']}"
    else:
        s = (f"R|{b['block_index']}|{b['giveaway_id']}|{b['draw_id']}|{b['seed']}|{b['total_tickets']}|"
             f"{b['tickets_hash']}|{b['winning_tickets']}|{b['ts_ms']}|{b['previous_hash']}")
    return sha(s)


def pick_winners(seed, gid, tickets, k):
    th = sha(",".join(f"{n}:{o}" for n, o in tickets))
    pool, win, j = list(tickets), [], 0
    while len(win) < k and pool:
        h = hashlib.sha256(f"{seed}:{gid}:{th}:{j}".encode()).digest()
        idx = int.from_bytes(h[:7], "big") % len(pool)
        n, o = pool[idx]
        win.append(n)
        pool = [t for t in pool if t[1] != o]
        j += 1
    return th, win


def verify(data):
    """Verifikasi seperti yang akan dilakukan aplikasi. Mengembalikan (valid, alasan)."""
    chain = data["chain"]
    prev = "0" * 64
    for b in chain:
        if b["previous_hash"] != prev:
            return False, "rantai hash tidak cocok (previous_hash)"
        if block_hash(b) != b["block_hash"]:
            return False, "rantai hash tidak cocok (block_hash)"
        prev = b["block_hash"]
    gid = data["giveaway"]["id"]
    commit = next((b for b in chain if b["giveaway_id"] == gid and b["block_type"] == "commit"), None)
    result = next((b for b in chain if b["giveaway_id"] == gid and b["block_type"] == "result"), None)
    if commit is None:
        return False, "commit block tidak ada"
    if data["first_ticket_ms"] is not None and commit["ts_ms"] > data["first_ticket_ms"]:
        return False, "commit dibuat setelah tiket"
    if result is None:
        return True, "belum di-draw (seed masih terkunci)"
    if sha(result["seed"]) != commit["seed_hash"]:
        return False, "seed tidak sesuai commitment"
    th, win = pick_winners(result["seed"], gid, [tuple(t) for t in data["tickets"]], commit["winner_count"])
    if th != result["tickets_hash"]:
        return False, "tickets_hash tidak cocok"
    if ",".join(map(str, win)) != result["winning_tickets"]:
        return False, "pemenang tidak cocok"
    return True, "valid"


# ---------------------------------------------------------------- pembantu data
def mk_giveaway(conn, admin_token, title="Tech Prize", start="-1 hour", end="+1 hour", draw="+2 hours",
                winners=2, max_tickets=10, category="tech", lat=-6.2, lng=106.8, **extra):
    payload_sql = """
      jsonb_build_object('title', %s::text, 'category', %s::text, 'prize_name', 'Laptop', 'prize_value_usd', 500,
        'latitude', %s::float8, 'longitude', %s::float8, 'organizer', 'Acme', 'description', 'desc',
        'start_at', (now() + %s::interval)::text, 'end_at', (now() + %s::interval)::text,
        'draw_at', (now() + %s::interval)::text, 'winner_count', %s::int, 'max_tickets_per_user', %s::int)
    """
    r = one(conn, f"select public.rpc_admin_upsert_giveaway(%s, {payload_sql})",
            (admin_token, title, category, lat, lng, start, end, draw, winners, max_tickets))
    return r


def gen_codes(conn, admin_token, gid, n, geo=None):
    if geo:
        r = one(conn, "select public.rpc_admin_generate_codes(%s,%s::uuid,%s,%s::float8,%s::float8,%s::numeric)",
                (admin_token, gid, n, geo[0], geo[1], Decimal(str(geo[2]))))
    else:
        r = one(conn, "select public.rpc_admin_generate_codes(%s,%s::uuid,%s)", (admin_token, gid, n))
    return r["codes"]


def redeem(conn, token, code, lat=None, lng=None):
    return one(conn, "select public.rpc_redeem_code(%s,%s,%s::float8,%s::float8)", (token, code, lat, lng))


# =====================================================================
def setup_database():
    print(f"Menyiapkan database {DBNAME} ...")
    admin = psycopg.connect(conninfo("postgres"), autocommit=True)
    admin.execute(f"drop database if exists {DBNAME}")
    admin.execute(f"create database {DBNAME}")
    admin.close()
    for f in ["tests/00_supabase_shim.sql", "01_schema.sql", "02_functions.sql"]:
        r = subprocess.run(["psql", "-h", HOST, "-p", PORT, "-U", USER, "-d", DBNAME, "-v", "ON_ERROR_STOP=1", "-q",
                            "-f", os.path.join(DBDIR, f)], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr)
            sys.exit(f"gagal memuat {f}")


def main():
    setup_database()
    su = superuser()
    a = anon()

    # ------------------------------------------------------------------
    section("1. Register dan salt")
    r = register(a, "alice", "alice@example.com", "Passw0rd!1", "Alice A")
    check("register berhasil", r["ok"], r)
    check("username duplikat (beda huruf besar) ditolak", register(a, "ALICE", "x@example.com", "Passw0rd!1")["error"] == "username_taken")
    check("email duplikat ditolak", register(a, "alice2", "ALICE@example.com", "Passw0rd!1")["error"] == "email_taken")
    check("username pendek ditolak", register(a, "abc", "b@example.com", "Passw0rd!1")["field"] == "username")
    check("email tidak valid ditolak", register(a, "bobby", "bukan-email", "Passw0rd!1")["field"] == "email")
    bad = rpc(a, "rpc_register", "carol1", "c@example.com", "Carol", os.urandom(16).hex(), "plaintext-password")
    check("hash non-hex ditolak (password plaintext tidak diterima)", bad.get("field") == "password_hash", bad)
    stored = one(su, "select password_hash from public.users where username='alice'")
    check("password disimpan sebagai bcrypt", stored.startswith("$2"), stored[:10])
    check("hash klien tidak tersimpan apa adanya", stored != client_hash("Passw0rd!1", one(su, "select salt from public.users where username='alice'")))
    s1 = rpc(a, "rpc_get_salt", "alice")["salt"]
    s2 = rpc(a, "rpc_get_salt", "ALICE@example.com")["salt"]
    check("salt sama untuk username dan email", s1 == s2 and len(s1) == 32)
    f1 = rpc(a, "rpc_get_salt", "tidak_ada")["salt"]
    f2 = rpc(a, "rpc_get_salt", "tidak_ada")["salt"]
    check("salt palsu konsisten dan berformat sama", f1 == f2 and len(f1) == 32 and f1 != s1)

    # ------------------------------------------------------------------
    section("2. Login, kunci akun, session")
    r = login(a, "alice", "salah")
    check("password salah -> invalid_credentials, sisa 4", r["error"] == "invalid_credentials" and r["attempts_left"] == 4, r)
    r = login(a, "alice@example.com", "salah")  # via email, hitungan dibagi dengan username
    check("email dan username berbagi hitungan gagal", r["attempts_left"] == 3, r)
    login(a, "alice", "salah")
    r = login(a, "alice", "salah")
    check("percobaan ke-4 masih invalid_credentials", r["attempts_left"] == 1, r)
    r = login(a, "alice", "salah")
    check("percobaan ke-5 -> locked 15 menit", r["error"] == "locked" and r["retry_after_seconds"] == 900, r)
    r = login(a, "alice", "Passw0rd!1")
    check("password benar saat terkunci tetap ditolak", r["error"] == "locked", r)
    su.execute("update public.login_attempts set locked_until = now() - interval '1 second'")
    r = login(a, "alice", "Passw0rd!1")
    check("login berhasil setelah kunci kedaluwarsa", r["ok"] and len(r["token"]) == 64, r)
    alice_tok = r["token"]
    check("data user dikembalikan tanpa hash/salt", "password_hash" not in r["user"] and "salt" not in r["user"])
    check("login tidak ada akun -> pesan sama", login(a, "hantu", "x")["error"] == "invalid_credentials")
    check("token tidak disimpan plaintext", one(su, "select count(*) from public.sessions where token_hash = %s", (alice_tok,)) == 0)
    check("token disimpan sebagai SHA-256", one(su, "select count(*) from public.sessions where token_hash = %s", (sha(alice_tok),)) == 1)
    r = rpc(a, "rpc_validate_session", alice_tok)
    check("validate_session ok", r["ok"] and r["user"]["username"] == "alice")
    check("validate_session token palsu", rpc(a, "rpc_validate_session", "0" * 64)["error"] == "invalid_session")
    check("RPC bertoken dengan token palsu -> exception 28000", sqlstate_of(lambda: rpc(a, "rpc_get_my_tickets", "0" * 64)) == "28000")
    su.execute("update public.sessions set expires_at = now() - interval '1 second' where token_hash = %s", (sha(alice_tok),))
    check("session kedaluwarsa ditolak", rpc(a, "rpc_validate_session", alice_tok)["error"] == "invalid_session")
    alice_tok = login(a, "alice", "Passw0rd!1")["token"]
    rpc(a, "rpc_logout", alice_tok)
    check("session tidak valid setelah logout", rpc(a, "rpc_validate_session", alice_tok)["error"] == "invalid_session")
    alice_tok = login(a, "alice", "Passw0rd!1")["token"]

    # ------------------------------------------------------------------
    section("3. Admin, giveaway, commit block")
    register(a, "admin01", "admin@example.com", "Adm1nPass!", "Admin")
    su.execute("update public.users set role='admin' where username='admin01'")
    adm = login(a, "admin01", "Adm1nPass!")["token"]
    check("non-admin membuat giveaway -> forbidden 42501",
          sqlstate_of(lambda: mk_giveaway(a, alice_tok)) == "42501")
    g1 = mk_giveaway(a, adm, title="Tech Prize", winners=2, max_tickets=3)
    check("admin membuat giveaway", g1["ok"] and g1["created"], g1)
    gid1 = g1["giveaway_id"]
    check("seed rahasia tersimpan", one(su, "select length(seed) from public.giveaway_secrets where giveaway_id=%s", (gid1,)) == 64)
    seed1 = one(su, "select seed from public.giveaway_secrets where giveaway_id=%s", (gid1,))
    check("seed_hash di giveaway = SHA-256(seed)", one(su, "select seed_hash from public.giveaways where id=%s", (gid1,)) == sha(seed1))
    commit = su.execute("select block_type, seed_hash, seed, winner_count, block_index from public.draw_chain where giveaway_id=%s", (gid1,)).fetchall()
    check("commit block terbentuk (seed belum dibuka)", len(commit) == 1 and commit[0][0] == "commit" and commit[0][2] is None and commit[0][1] == sha(seed1), commit)
    check("block genesis memakai previous_hash nol", one(su, "select previous_hash from public.draw_chain where block_index=1") == "0" * 64)
    bad = mk_giveaway(a, adm, title="X", start="+2 hours", end="+1 hour", draw="+3 hours")
    check("urutan waktu tidak valid ditolak", bad["error"] == "invalid_input", bad)
    check("winner_count 0 ditolak", mk_giveaway(a, adm, winners=0)["error"] == "invalid_input")
    check("kategori tidak dikenal ditolak", mk_giveaway(a, adm, category="senjata")["error"] == "invalid_input")
    check("giveaway gagal tidak meninggalkan seed/block yatim",
          one(su, "select count(*) from public.giveaway_secrets") == 1 and one(su, "select count(*) from public.draw_chain") == 1)

    # ubah giveaway: seed tidak berubah, winner_count terkunci setelah mulai
    r = one(a, "select public.rpc_admin_upsert_giveaway(%s, jsonb_build_object('id', %s::text, 'title', 'Tech Prize v2'))", (adm, gid1))
    check("ubah judul diizinkan", r["ok"] and not r["created"], r)
    check("seed tidak berubah saat giveaway diubah", one(su, "select seed from public.giveaway_secrets where giveaway_id=%s", (gid1,)) == seed1)
    check("jumlah block tidak bertambah saat diubah", one(su, "select count(*) from public.draw_chain where giveaway_id=%s", (gid1,)) == 1)
    r = one(a, "select public.rpc_admin_upsert_giveaway(%s, jsonb_build_object('id', %s::text, 'winner_count', 5))", (adm, gid1))
    check("winner_count terkunci setelah giveaway mulai", r["error"] == "winner_count_locked", r)
    check("block draw_chain tidak bisa diubah (UPDATE)", sqlstate_of(lambda: su.execute("update public.draw_chain set ts_ms = 1")) == "42501")
    check("block draw_chain tidak bisa dihapus (DELETE)", sqlstate_of(lambda: su.execute("delete from public.draw_chain")) == "42501")
    check("draw_chain tidak bisa di-TRUNCATE", sqlstate_of(lambda: su.execute("truncate public.draw_chain")) == "42501")

    # ------------------------------------------------------------------
    section("4. Kode dan input kode")
    codes = gen_codes(a, adm, gid1, 40)
    check("40 kode unik dengan format XXXX-XXXX-XXXX", len(set(codes)) == 40 and all(len(c) == 14 and c[4] == "-" for c in codes))
    check("generate kode oleh non-admin ditolak", sqlstate_of(lambda: gen_codes(a, alice_tok, gid1, 1)) == "42501")
    check("generate 0 kode ditolak", one(a, "select public.rpc_admin_generate_codes(%s,%s::uuid,0)", (adm, gid1))["error"] == "invalid_input")

    r = redeem(a, alice_tok, "ABC")
    check("format salah -> invalid_format", r["error"] == "invalid_format", r)
    r = redeem(a, alice_tok, "AAAA-BBBB-CCCC")
    check("kode tidak ada -> code_not_found", r["error"] == "code_not_found", r)
    r = redeem(a, alice_tok, codes[0].lower().replace("-", " "))
    check("kode huruf kecil tanpa strip diterima, tiket #1", r["ok"] and r["ticket"]["ticket_number"] == 1, r)
    r = redeem(a, alice_tok, codes[0])
    check("kode dipakai ulang -> code_used", r["error"] == "code_used", r)
    check("tiket berurutan #2", redeem(a, alice_tok, codes[1])["ticket"]["ticket_number"] == 2)
    check("tiket berurutan #3", redeem(a, alice_tok, codes[2])["ticket"]["ticket_number"] == 3)
    r = redeem(a, alice_tok, codes[3])
    check("batas 3 tiket per user -> ticket_limit", r["error"] == "ticket_limit", r)
    check("kode yang ditolak karena batas tetap belum terpakai", one(su, "select is_used from public.codes where code=%s", (codes[3],)) is False)
    mine = rpc(a, "rpc_get_my_tickets", alice_tok)
    check("rpc_get_my_tickets: 3 tiket, eligible, kode disamarkan",
          len(mine) == 3 and all(t["result"] == "eligible" for t in mine) and mine[0]["code_masked"].startswith("****-****-"), mine)
    notifs = rpc(a, "rpc_get_notifications", alice_tok)
    check("notifikasi tiket dibuat", len(notifs) == 3 and notifs[0]["type"] == "ticket_created", notifs)
    check("badge first_ticket dan early_bird", set(rpc(a, "rpc_validate_session", alice_tok)["user"]["badges"]) >= {"first_ticket"})

    # pembatasan kegagalan: 5 gagal / 10 menit
    register(a, "bobby", "bobby@example.com", "Passw0rd!1", "Bobby")
    bob_tok = login(a, "bobby", "Passw0rd!1")["token"]
    for i in range(5):
        redeem(a, bob_tok, f"ZZZZ-ZZZZ-ZZZ{i}")
    r = redeem(a, bob_tok, codes[10])
    check("kegagalan ke-6 dalam 10 menit -> rate_limited (walau kode benar)", r["error"] == "rate_limited" and r["retry_after_seconds"] > 0, r)
    su.execute("update public.code_attempts set attempted_at = now() - interval '11 minutes'")
    check("rate limit lepas setelah 10 menit", redeem(a, bob_tok, codes[10])["ok"])

    # geo-restricted
    g2 = mk_giveaway(a, adm, title="Geo Prize", winners=1, category="travel", lat=-6.2, lng=106.8)
    gcodes = gen_codes(a, adm, g2["giveaway_id"], 3, geo=(-6.2, 106.8, 5))
    r = redeem(a, bob_tok, gcodes[0])
    check("kode geo tanpa lokasi -> location_required", r["error"] == "location_required", r)
    r = redeem(a, bob_tok, gcodes[0], -6.9175, 107.6191)  # Bandung
    check("kode geo di luar radius -> out_of_area", r["error"] == "out_of_area", r)
    near = (-6.205, 106.82)  # sekitar 2,3 km dari pusat radius (-6.2, 106.8); radius 5 km
    r = redeem(a, bob_tok, gcodes[0], *near)
    check("kode geo di dalam radius diterima", r["ok"], r)
    dist = one(su, "select public.fn_distance_km(-6.2, 106.8, %s, %s)", near)
    check("jarak haversine masuk akal (2-3 km)", 2.0 < dist < 3.0, dist)
    edge = one(su, "select public.fn_distance_km(-6.2, 106.8, -6.2088, 106.8456)")
    check("titik uji awal memang di luar radius 5 km (5,1 km)", 5.0 < edge < 5.3, edge)

    # kondisi giveaway
    g3 = mk_giveaway(a, adm, title="Besok", start="+1 hour", end="+2 hours", draw="+3 hours")
    c3 = gen_codes(a, adm, g3["giveaway_id"], 1)
    check("giveaway belum mulai -> giveaway_not_started", redeem(a, bob_tok, c3[0])["error"] == "giveaway_not_started")
    g4 = su.execute("""insert into public.giveaways(title, category, prize_name, prize_value_usd, start_at, end_at, draw_at,
                       winner_count, seed_hash) values ('Tanpa Commit','tech','X',1, now()-interval '1 hour', now()+interval '1 hour',
                       now()+interval '2 hours', 1, %s) returning id""", (sha("x"),)).fetchone()[0]
    su.execute("insert into public.codes(giveaway_id, code) values (%s, 'NOCM-MITT-0001')", (g4,))
    check("giveaway tanpa commit block ditolak -> giveaway_not_ready", redeem(a, bob_tok, "NOCM-MITT-0001")["error"] == "giveaway_not_ready")

    # ------------------------------------------------------------------
    section("5. Konkurensi")
    register(a, "carol1", "carol@example.com", "Passw0rd!1", "Carol")
    register(a, "dave01", "dave@example.com", "Passw0rd!1", "Dave")
    carol = login(a, "carol1", "Passw0rd!1")["token"]
    dave = login(a, "dave01", "Passw0rd!1")["token"]
    gc = mk_giveaway(a, adm, title="Race", winners=1, max_tickets=50)
    race_codes = gen_codes(a, adm, gc["giveaway_id"], 30)
    barrier = threading.Barrier(2)

    def race(tok):
        c = anon()
        barrier.wait()
        res = redeem(c, tok, race_codes[0])
        c.close()
        return res

    with cf.ThreadPoolExecutor(2) as ex:
        res = list(ex.map(race, [carol, dave]))
    oks = [x for x in res if x["ok"]]
    check("dua pengguna memakai kode yang sama bersamaan: tepat satu berhasil",
          len(oks) == 1 and sum(1 for x in res if not x["ok"] and x["error"] == "code_used") == 1, res)

    toks = []
    for i in range(12):
        register(a, f"racer{i:02d}", f"racer{i}@example.com", "Passw0rd!1", f"Racer {i}")
        toks.append(login(a, f"racer{i:02d}", "Passw0rd!1")["token"])

    def buy(args):
        tok, code = args
        c = anon()
        try:
            return redeem(c, tok, code)
        finally:
            c.close()

    with cf.ThreadPoolExecutor(12) as ex:
        res = list(ex.map(buy, [(toks[i], race_codes[1 + i]) for i in range(12)]))
    nums = sorted(x["ticket"]["ticket_number"] for x in res if x["ok"])
    prior = one(su, "select count(*) from public.tickets where giveaway_id=%s", (gc["giveaway_id"],)) - 12
    check("12 pembelian paralel: semua berhasil", len(nums) == 12, res)
    check("nomor tiket unik berurutan tanpa celah", nums == list(range(prior + 1, prior + 13)), nums)

    # ------------------------------------------------------------------
    section("6. Search")
    mk_giveaway(a, adm, title="Gaming Mouse Giveaway", category="gaming", lat=-6.9175, lng=107.6191, winners=1)  # Bandung
    s = rpc(a, "rpc_search_giveaways")
    check("search default: hanya giveaway aktif", len(s) >= 4 and all(x["status"] != "drawn" for x in s))
    s = one(a, "select public.rpc_search_giveaways(%s)", ("gaming",))
    check("search kata kunci", len(s) == 1 and s[0]["title"].startswith("Gaming"), s)
    s = one(a, "select public.rpc_search_giveaways(p_category => %s)", ("travel",))
    check("filter kategori", len(s) == 1 and s[0]["category"] == "travel")
    s = one(a, "select public.rpc_search_giveaways(p_lat => -6.2::float8, p_lng => 106.8::float8, p_radius_km => 10, p_sort => 'nearest')")
    check("filter radius 10 km dari Jakarta tidak memuat Bandung", s and all(x["distance_km"] <= 10 for x in s) and not any(x["category"] == "gaming" for x in s))
    s = one(a, "select public.rpc_search_giveaways(p_lat => -6.2::float8, p_lng => 106.8::float8, p_sort => 'nearest')")
    d = [x["distance_km"] for x in s]
    known = [x for x in d if x is not None]
    check("sort terdekat menaik, tanpa koordinat di urutan akhir",
          known == sorted(known) and d == known + [None] * (len(d) - len(known)), d)
    s = one(a, "select public.rpc_search_giveaways(p_limit => 2, p_offset => 0)")
    s2 = one(a, "select public.rpc_search_giveaways(p_limit => 2, p_offset => 2)")
    check("paginasi tidak tumpang tindih", len(s) == 2 and not ({x["id"] for x in s} & {x["id"] for x in s2}))
    s = one(a, "select public.rpc_search_giveaways(%s)", ("100%",))
    check("karakter wildcard di-escape", s == [])
    s = one(a, "select public.rpc_search_giveaways(p_status => 'upcoming')")
    check("filter upcoming", len(s) == 1 and s[0]["title"] == "Besok")

    # ------------------------------------------------------------------
    section("7. Draw demo (admin) dan verifikasi independen")
    # Peserta: alice (3 tiket), bobby, carol, 12 racers pada giveaway 'Race' (gc); jalankan draw 3 pemenang
    one(a, "select public.rpc_admin_upsert_giveaway(%s, jsonb_build_object('id', %s::text, 'title', 'Race'))", (adm, gc["giveaway_id"]))
    # beli lebih banyak tiket oleh racer00 agar kasus 'satu pengguna satu hadiah' teruji
    more = gen_codes(a, adm, gc["giveaway_id"], 6)
    for c in more:
        redeem(a, toks[0], c)
    total = one(su, "select count(*) from public.tickets where giveaway_id=%s", (gc["giveaway_id"],))
    check("racer00 memiliki banyak tiket", one(su, "select count(*) from public.tickets t join public.users u on u.id=t.user_id where t.giveaway_id=%s and u.username='racer00'", (gc["giveaway_id"],)) >= 7)
    check("non-admin tidak bisa run draw", sqlstate_of(lambda: rpc(a, "rpc_admin_run_draw", alice_tok, gc["giveaway_id"], casts=["", "::uuid"])) == "42501")
    r = rpc(a, "rpc_admin_run_draw", adm, gc["giveaway_id"], casts=["", "::uuid"])
    check("admin menjalankan draw demo", r["ok"] and r["status"] == "completed", r)
    check("draw tercatat trigger admin_demo", one(su, "select trigger_type from public.draws where giveaway_id=%s", (gc["giveaway_id"],)) == "admin_demo")
    check("draw kedua ditolak (idempotent)", rpc(a, "rpc_admin_run_draw", adm, gc["giveaway_id"], casts=["", "::uuid"])["error"] == "already_drawn")
    check("hanya satu draw dan satu result block", one(su, "select count(*) from public.draws where giveaway_id=%s", (gc["giveaway_id"],)) == 1
          and one(su, "select count(*) from public.draw_chain where giveaway_id=%s and block_type='result'", (gc["giveaway_id"],)) == 1)
    check("status giveaway = drawn", one(su, "select status from public.giveaways where id=%s", (gc["giveaway_id"],)) == "drawn")
    w = rpc(a, "rpc_get_winners", gc["giveaway_id"], casts=["::uuid"])
    check("pemenang publik: nama tersamar", w["drawn"] and len(w["winners"]) == 1 and "***" in w["winners"][0]["name"], w)
    vd = rpc(a, "rpc_get_verification_data", gc["giveaway_id"], casts=["::uuid"])
    ok, why = verify(vd)
    check("verifikasi independen (Python) -> valid", ok, why)
    check("fn_verify_chain (server) semua ok", all(r[1] for r in su.execute("select * from public.fn_verify_chain()").fetchall()))
    check("daftar tiket tidak membuka user_id", all(len(t) == 2 and len(t[1]) == 12 for t in vd["tickets"]))

    # banyak pemenang + satu pengguna satu hadiah
    gm = mk_giveaway(a, adm, title="Multi", winners=5, max_tickets=10)
    cm = gen_codes(a, adm, gm["giveaway_id"], 40)
    k = 0
    for tok in [alice_tok, bob_tok, carol, dave] + toks[:6]:
        for _ in range(3):
            redeem(a, tok, cm[k]); k += 1
    r = rpc(a, "rpc_admin_run_draw", adm, gm["giveaway_id"], casts=["", "::uuid"])
    check("draw 5 pemenang dari 10 peserta", r["ok"] and len(r["winning_tickets"]) == 5, r)
    wu = su.execute("select user_id from public.winners where giveaway_id=%s", (gm["giveaway_id"],)).fetchall()
    check("pemenang semua pengguna berbeda", len({x[0] for x in wu}) == 5)
    vd = rpc(a, "rpc_get_verification_data", gm["giveaway_id"], casts=["::uuid"])
    check("verifikasi independen draw multi-pemenang valid", verify(vd)[0], verify(vd))
    check("hasil Python = hasil SQL", pick_winners(
        next(b for b in vd["chain"] if b["block_type"] == "result" and b["giveaway_id"] == gm["giveaway_id"])["seed"],
        gm["giveaway_id"], [tuple(t) for t in vd["tickets"]], 5)[1] == r["winning_tickets"])
    res_by_user = {}
    for tok, name in [(alice_tok, "alice"), (bob_tok, "bobby")]:
        res_by_user[name] = {t["result"] for t in rpc(a, "rpc_get_my_tickets", tok) if t["giveaway_id"] == gm["giveaway_id"]}
    check("status tiket setelah draw: winner / not_selected", all(x <= {"winner", "not_selected"} for x in res_by_user.values()), res_by_user)
    nw = one(su, "select count(*) from public.notifications where giveaway_id=%s and type='winner'", (gm["giveaway_id"],))
    nr = one(su, "select count(*) from public.notifications where giveaway_id=%s and type='draw_result'", (gm["giveaway_id"],))
    check("notifikasi: 5 pemenang dan 5 peserta lain", (nw, nr) == (5, 5), (nw, nr))
    check("setelah draw, input kode ditolak", redeem(a, alice_tok, cm[39])["error"] in ("giveaway_ended", "code_used"))

    # peserta kurang dari jumlah pemenang
    gl = mk_giveaway(a, adm, title="Sedikit", winners=5, max_tickets=10)
    cl = gen_codes(a, adm, gl["giveaway_id"], 3)
    for c in cl:
        redeem(a, carol, c)
    r = rpc(a, "rpc_admin_run_draw", adm, gl["giveaway_id"], casts=["", "::uuid"])
    check("satu peserta, 3 tiket, 5 hadiah -> hanya 1 pemenang", r["ok"] and len(r["winning_tickets"]) == 1, r)
    check("verifikasi valid", verify(rpc(a, "rpc_get_verification_data", gl["giveaway_id"], casts=["::uuid"]))[0])

    # tanpa peserta
    ge = mk_giveaway(a, adm, title="Kosong", winners=2)
    r = rpc(a, "rpc_admin_run_draw", adm, ge["giveaway_id"], casts=["", "::uuid"])
    check("draw tanpa tiket -> no_participants, tanpa error", r["ok"] and r["status"] == "no_participants" and r["winning_tickets"] == [], r)
    check("verifikasi draw kosong valid", verify(rpc(a, "rpc_get_verification_data", ge["giveaway_id"], casts=["::uuid"]))[0])

    # draw sebelum mulai ditolak
    r = rpc(a, "rpc_admin_run_draw", adm, g3["giveaway_id"], casts=["", "::uuid"])
    check("draw demo pada giveaway belum mulai ditolak", r["error"] == "not_started", r)
    su.execute("update public.app_config set value='false' where key='demo_draw_enabled'")
    check("flag demo dimatikan -> demo_disabled", rpc(a, "rpc_admin_run_draw", adm, g3["giveaway_id"], casts=["", "::uuid"])["error"] == "demo_disabled")
    su.execute("update public.app_config set value='true' where key='demo_draw_enabled'")

    # ------------------------------------------------------------------
    section("8. Keamanan commit-reveal dan manipulasi")
    gt = mk_giveaway(a, adm, title="Tamper", winners=1)
    ct = gen_codes(a, adm, gt["giveaway_id"], 4)
    for c in ct[:3]:
        redeem(a, dave, c)
    su.execute("update public.giveaway_secrets set seed = %s where giveaway_id=%s", (os.urandom(32).hex(), gt["giveaway_id"]))
    r = rpc(a, "rpc_admin_run_draw", adm, gt["giveaway_id"], casts=["", "::uuid"])
    check("seed diganti sebelum draw -> draw ditolak (seed_mismatch)", r["error"] == "seed_mismatch", r)
    check("status giveaway tidak berubah dan tidak ada pemenang",
          one(su, "select status from public.giveaways where id=%s", (gt["giveaway_id"],)) != "drawn"
          and one(su, "select count(*) from public.winners where giveaway_id=%s", (gt["giveaway_id"],)) == 0
          and one(su, "select count(*) from public.draws where giveaway_id=%s", (gt["giveaway_id"],)) == 0)
    check("kejadian error tercatat", one(su, "select count(*) from public.system_events where event='draw_seed_mismatch'") == 1)

    # manipulasi data blok (hanya mungkin dengan menonaktifkan trigger) harus terdeteksi
    vd_before = rpc(a, "rpc_get_verification_data", gc["giveaway_id"], casts=["::uuid"])
    check("sebelum manipulasi valid", verify(vd_before)[0])
    su.execute("alter table public.draw_chain disable trigger draw_chain_no_update_delete")
    su.execute("update public.draw_chain set winning_tickets = '999' where giveaway_id=%s and block_type='result'", (gc["giveaway_id"],))
    ok, why = verify(rpc(a, "rpc_get_verification_data", gc["giveaway_id"], casts=["::uuid"]))
    check("hasil diubah -> verifikasi mendeteksi", not ok, why)
    bad_rows = [r for r in su.execute("select * from public.fn_verify_chain()").fetchall() if not r[1]]
    check("fn_verify_chain mendeteksi block rusak", len(bad_rows) >= 1, bad_rows)
    su.execute("update public.draw_chain set winning_tickets = %s where giveaway_id=%s and block_type='result'",
               (vd_before["chain"][-1]["winning_tickets"] if vd_before["chain"][-1]["giveaway_id"] == gc["giveaway_id"]
                else next(b for b in vd_before["chain"] if b["block_type"] == "result" and b["giveaway_id"] == gc["giveaway_id"])["winning_tickets"],
                gc["giveaway_id"]))
    # ubah seed di result block + hitung ulang hash agar rantai tampak konsisten: tetap harus gagal di cek seed
    rb = next(b for b in vd_before["chain"] if b["block_type"] == "result" and b["giveaway_id"] == gc["giveaway_id"])
    fake = dict(rb, seed=os.urandom(32).hex())
    fake_hash = block_hash(fake)
    forged = json.loads(json.dumps(vd_before))
    for b in forged["chain"]:
        if b["block_index"] == rb["block_index"]:
            b["seed"], b["block_hash"] = fake["seed"], fake_hash
    # blok setelahnya (jika ada) akan tak cocok previous_hash; kasus terburuk bagi pemalsu = blok terakhir
    ok, why = verify(forged)
    check("seed palsu dengan hash dihitung ulang tetap terdeteksi", not ok, why)
    su.execute("alter table public.draw_chain enable trigger draw_chain_no_update_delete")
    check("setelah dipulihkan valid kembali", verify(rpc(a, "rpc_get_verification_data", gc["giveaway_id"], casts=["::uuid"]))[0])

    # commit dibuat setelah tiket pertama -> terdeteksi
    forged = json.loads(json.dumps(vd_before))
    forged["first_ticket_ms"] = 1
    ok, why = verify(forged)
    check("commit setelah tiket pertama terdeteksi", (not ok) and "commit" in why, why)

    # ------------------------------------------------------------------
    section("9. Scheduler (fn_run_due_draws)")
    gs = mk_giveaway(a, adm, title="Auto", winners=1, start="-1 hour", end="+3 seconds", draw="+4 seconds")
    cs = gen_codes(a, adm, gs["giveaway_id"], 3)
    for c in cs:
        redeem(a, carol, c)
    n = one(su, "select public.fn_run_due_draws()")
    check("sebelum jatuh tempo: scheduler tidak menjalankan draw giveaway ini",
          one(su, "select status from public.giveaways where id=%s", (gs["giveaway_id"],)) != "drawn", n)
    time.sleep(5)
    n = one(su, "select public.fn_run_due_draws()")
    check("setelah jatuh tempo: scheduler menjalankan draw otomatis", n >= 1 and
          one(su, "select trigger_type from public.draws where giveaway_id=%s", (gs["giveaway_id"],)) == "scheduler")
    check("scheduler dijalankan lagi: tidak ada draw ganda", one(su, "select public.fn_run_due_draws()") == 0)
    check("hasil scheduler lolos verifikasi", verify(rpc(a, "rpc_get_verification_data", gs["giveaway_id"], casts=["::uuid"]))[0])
    check("status giveaway diperbarui scheduler", one(su, "select public.fn_refresh_giveaway_status()") >= 0)

    # ------------------------------------------------------------------
    section("10. Game, feedback, profil, aktivitas")
    r = one(a, "select public.rpc_submit_game_score(%s, 5, 30, true, 40)", (alice_tok,))
    check("skor game: XP = bintang*10 + sisa waktu", r["ok"] and r["xp_earned"] == 80 and r["user"]["xp"] == 80, r)
    check("badge first_maze_clear", "first_maze_clear" in r["user"]["badges"])
    r = one(a, "select public.rpc_submit_game_score(%s, 30, 60, true, 20)", (alice_tok,))
    check("batas XP harian 200", r["xp_earned"] == 120 and r["daily_xp_total"] == 200 and r["daily_cap_reached"], r)
    r = one(a, "select public.rpc_submit_game_score(%s, 10, 10, true, 20)", (alice_tok,))
    check("setelah batas harian XP tidak bertambah", r["xp_earned"] == 0 and r["user"]["xp"] == 200, r)
    check("input game tidak valid ditolak", one(a, "select public.rpc_submit_game_score(%s, 99, 10, true, 20)", (alice_tok,))["error"] == "invalid_input")
    check("level = xp/500 + 1", rpc(a, "rpc_validate_session", alice_tok)["user"]["level"] == 1)
    lb = rpc(a, "rpc_get_leaderboard", alice_tok)
    check("leaderboard", len(lb) == 1 and lb[0]["username"] == "alice" and lb[0]["rank"] == 1, lb)
    check("leaderboard butuh session", sqlstate_of(lambda: rpc(a, "rpc_get_leaderboard", "0" * 64)) == "28000")

    check("feedback kosong ditolak", rpc(a, "rpc_submit_feedback", alice_tok, "  ", "ok")["field"] == "suggestion")
    check("feedback > 1000 karakter ditolak", rpc(a, "rpc_submit_feedback", alice_tok, "x" * 1001, "ok")["field"] == "suggestion")
    check("feedback tersimpan", rpc(a, "rpc_submit_feedback", alice_tok, "Tambah materi sensor", "Seru")["ok"])
    check("riwayat feedback", len(rpc(a, "rpc_get_my_feedback", alice_tok)) == 1)
    r = rpc(a, "rpc_update_profile", alice_tok, "Alice Baru", "https://example.com/a.jpg")
    check("update profil", r["ok"] and r["user"]["full_name"] == "Alice Baru" and r["user"]["photo_url"].endswith("a.jpg"), r)
    check("log aktivitas valid", rpc(a, "rpc_log_activity", alice_tok, "view_giveaway", gid1, "tech", casts=["", "", "::uuid", ""])["ok"])
    check("log aktivitas dengan tipe server-only ditolak", rpc(a, "rpc_log_activity", alice_tok, "ticket_created", gid1, "tech", casts=["", "", "::uuid", ""])["error"] == "invalid_input")
    aff = rpc(a, "rpc_get_category_affinity", alice_tok)
    n_tech = one(su, "select count(*) from public.tickets t join public.giveaways g on g.id=t.giveaway_id "
                     "join public.users u on u.id=t.user_id where u.username='alice' and g.category='tech'")
    check("alice punya 6 tiket tech (3 Tech Prize + 3 Multi)", n_tech == 6, n_tech)
    check("afinitas kategori: tiket*3 + lihat*1", aff.get("tech") == 6 * 3 + 1, aff)
    ns = rpc(a, "rpc_get_notifications", alice_tok)
    first_id = ns[-1]["id"]
    newer = one(a, "select public.rpc_get_notifications(%s, %s::bigint)", (alice_tok, first_id))
    check("polling notifikasi: hanya yang lebih baru dari after_id", all(n["id"] > first_id for n in newer) and len(newer) == len(ns) - 1)
    r = one(a, "select public.rpc_mark_notifications_read(%s, null::bigint[])", (alice_tok,))
    check("tandai semua notifikasi dibaca", r["ok"] and r["updated"] >= 1)
    check("notifikasi milik user lain tidak terlihat",
          all(n["id"] not in {x["id"] for x in rpc(a, "rpc_get_notifications", bob_tok)} for n in ns))

    # ------------------------------------------------------------------
    section("11. Hak akses role anon")
    def denied(sql):
        return sqlstate_of(lambda: a.execute(sql).fetchall()) == "42501"

    for t in ["users", "sessions", "login_attempts", "giveaway_secrets", "codes", "code_attempts", "tickets", "draws",
              "winners", "notifications", "user_activity", "game_scores", "user_badges", "feedback", "app_config", "system_events"]:
        check(f"anon tidak bisa SELECT {t}", denied(f"select * from public.{t} limit 1"))
    check("anon bisa SELECT giveaways", not denied("select id from public.giveaways limit 1"))
    check("anon bisa SELECT draw_chain", not denied("select id from public.draw_chain limit 1"))
    check("draw_chain publik: seed commit block null sebelum draw",
          one(a, "select count(*) from public.draw_chain c where c.block_type='commit' and c.seed is not null") == 0)
    check("anon tidak bisa UPDATE giveaways", denied("update public.giveaways set title='x'"))
    check("anon tidak bisa INSERT tickets", denied("insert into public.tickets(giveaway_id, ticket_number, user_id, code_id) values (gen_random_uuid(),1,gen_random_uuid(),gen_random_uuid())"))
    check("anon tidak bisa DELETE draw_chain", denied("delete from public.draw_chain"))
    check("anon tidak bisa INSERT winners", denied("insert into public.winners(draw_id, giveaway_id, ticket_id, user_id, rank) values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1)"))
    for f in ["fn_execute_draw(gen_random_uuid(),'admin_demo')", "fn_require_session('x')", "fn_run_due_draws()",
              "fn_append_block('commit',gen_random_uuid(),null,null,null,1,null,null,null)", "fn_verify_chain()", "fn_cleanup()"]:
        check(f"anon tidak bisa EXECUTE {f.split('(')[0]}", denied(f"select public.{f}"))
    check("anon bisa EXECUTE rpc_search_giveaways", not denied("select public.rpc_search_giveaways()"))

    print(f"\nHASIL: {passed} lulus, {len(failed)} gagal")
    if failed:
        print("Gagal:", *failed, sep="\n  - ")
        sys.exit(1)


if __name__ == "__main__":
    main()
