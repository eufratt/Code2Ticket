"""
Menghitung vektor kontrak memakai implementasi ACUAN di backend/test/reference/test_m1.py
(client_hash, block_hash, pick_winners, verify) untuk input dari stdin (JSON), hasil ke stdout (JSON).

test_m1.py mengimpor psycopg di tingkat modul; modul tiruan dipasang agar fungsi acuannya bisa dimuat
tanpa database. Fungsi yang dipakai tidak menyentuh psycopg.
"""
import hashlib
import importlib.util
import json
import sys
import types

ref_path = sys.argv[1]
sys.modules.setdefault("psycopg", types.ModuleType("psycopg"))
spec = importlib.util.spec_from_file_location("test_m1_ref", ref_path)
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)

req = json.loads(sys.stdin.buffer.read().decode("utf-8"))  # Windows: stdin teks bukan UTF-8
out = {}

out["client_hash"] = [ref.client_hash(pw, salt) for pw, salt in req.get("client_hash", [])]
out["block_hash"] = [ref.block_hash(b) for b in req.get("blocks", [])]

picks = []
for c in req.get("picks", []):
    th, win = ref.pick_winners(c["seed"], c["gid"], [tuple(t) for t in c["tickets"]], c["k"])
    picks.append({"tickets_hash": th, "winners": win})
out["picks"] = picks

out["owner_key"] = [hashlib.sha256(f"{u}:{g}".encode()).hexdigest()[:12] for u, g in req.get("owner_key", [])]
out["sha"] = [ref.sha(s) for s in req.get("sha", [])]

if "verify" in req:
    ok, why = ref.verify(req["verify"])
    out["verify"] = {"ok": ok, "why": why}

json.dump(out, sys.stdout)
