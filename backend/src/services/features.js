import { z } from 'zod';
import { withTx } from '../db.js';
import { cpLen, fail, ok, parseInput, pgTrim } from '../lib/util.js';
import { awardBadges, userJson } from './users.js';

const blank = (v) => (v === '' || v == null ? undefined : v);
const intQ = z.preprocess(blank, z.coerce.number().int().optional());

// ---------------------------------------------------------------- notifikasi
const notifQuerySchema = z.object({ after_id: intQ, limit: intQ });

export async function getNotifications(pool, user, query) {
  const p = parseInput(notifQuerySchema, query);
  if (p.error) return p.error;
  const limit = Math.min(Math.max(p.data.limit ?? 50, 1), 200);
  const r = await pool.query(
    `select id, type, title, body, giveaway_id, is_read, created_at
       from notifications where user_id = $1 and id > $2::bigint order by id desc limit $3`,
    [user.id, p.data.after_id ?? 0, limit],
  );
  return r.rows;
}

const markSchema = z.object({ ids: z.array(z.int().positive()).max(1000).nullish() });

export async function markNotificationsRead(pool, user, body) {
  const p = parseInput(markSchema, body);
  if (p.error) return p.error;
  const r = await pool.query(
    'update notifications set is_read = true where user_id = $1 and not is_read and ($2::bigint[] is null or id = any($2::bigint[]))',
    [user.id, p.data.ids ?? null],
  );
  return ok({ updated: r.rowCount });
}

// ---------------------------------------------------------------- feedback
const feedbackSchema = z.object({
  suggestion: z.string().transform(pgTrim).pipe(z.string().refine((s) => cpLen(s) >= 1 && cpLen(s) <= 1000)),
  impression: z.string().transform(pgTrim).pipe(z.string().refine((s) => cpLen(s) >= 1 && cpLen(s) <= 1000)),
});

export async function submitFeedback(pool, user, body) {
  const p = parseInput(feedbackSchema, body);
  if (p.error) return p.error;
  await pool.query('insert into feedback(user_id, suggestion, impression) values ($1,$2,$3)', [
    user.id, p.data.suggestion, p.data.impression,
  ]);
  return ok();
}

export async function getMyFeedback(pool, user) {
  const r = await pool.query(
    'select id, suggestion, impression, created_at from feedback where user_id = $1 order by created_at desc, id desc',
    [user.id],
  );
  return r.rows;
}

// ---------------------------------------------------------------- aktivitas dan afinitas
const activitySchema = z.object({
  type: z.enum(['view_giveaway', 'search', 'game_played', 'chat']), // 'ticket_created' hanya dari server
  giveaway_id: z.uuid().nullish(),
  category: z.string().nullish(),
});

export async function logActivity(pool, user, body) {
  const p = parseInput(activitySchema, body);
  if (p.error) return p.error;
  const { type, giveaway_id, category } = p.data;
  await pool.query(
    `insert into user_activity(user_id, activity_type, giveaway_id, category)
     values ($1, $2, (select id from giveaways where id = $3::uuid), $4)`, // null bila giveaway tidak ada
    [user.id, type, giveaway_id ?? null, category == null ? null : [...category].slice(0, 30).join('')],
  );
  return ok();
}

// Masukan rekomendasi: skor per kategori = tiket*3 + lihat*1 (90 hari terakhir)
export async function getCategoryAffinity(pool, user) {
  const r = await pool.query(
    `select category, sum(score)::int as score from (
       select g.category, 3 as score from tickets t join giveaways g on g.id = t.giveaway_id
        where t.user_id = $1 and t.created_at > now() - interval '90 days'
       union all
       select a.category, 1 from user_activity a
        where a.user_id = $1 and a.activity_type = 'view_giveaway'
          and a.category is not null and a.created_at > now() - interval '90 days'
     ) s group by category`,
    [user.id],
  );
  return Object.fromEntries(r.rows.map((x) => [x.category, x.score]));
}

// ---------------------------------------------------------------- game
const DAILY_XP_CAP = 200;
const scoreSchema = z.object({
  stars: z.int().min(0).max(30),
  seconds_left: z.int().min(0).max(60),
  cleared: z.boolean().nullish(),
  duration_sec: z.int().min(0).max(600),
});

// Tingkat labirin di app (app\libeatures\game\maze.dart, MazeLevel): bintang dan batas waktu detik.
// Mudah 5/60, Sedang 8/55, Sulit 12/50. Hasil yang tidak cocok dengan satu pun tingkat = tidak masuk akal.
const MAZE_LEVELS = [{ stars: 5, seconds: 60 }, { stars: 8, seconds: 55 }, { stars: 12, seconds: 50 }];
const DURATION_SLACK = 2; // pembulatan elapsed/timeLeft di klien
const MAX_SCORES_PER_HOUR = 60;

// Bintang <= jumlah item tingkat, sisa waktu + lama main <= batas waktu tingkat, dan lama main tidak mustahil singkat.
export function plausibleScore({ stars, seconds_left, duration_sec, cleared }) {
  const minDuration = cleared || stars > 0 ? Math.max(3, stars) : 0;
  if (duration_sec < minDuration) return false;
  return MAZE_LEVELS.some((l) => stars <= l.stars && seconds_left <= l.seconds && duration_sec + seconds_left <= l.seconds + DURATION_SLACK);
}

export async function submitGameScore(pool, user, body) {
  const p = parseInput(scoreSchema, body);
  if (p.error) return fail('invalid_input');
  const { stars, seconds_left, duration_sec } = p.data;
  const cleared = p.data.cleared ?? false;
  if (!plausibleScore({ stars, seconds_left, duration_sec, cleared })) return fail('invalid_score');
  const left = cleared ? seconds_left : 0;
  const xpRaw = stars * 10 + left;
  const score = stars * 100 + left * 10;

  return withTx(pool, async (c) => {
    await c.query('select 1 from users where id = $1 for no key update', [user.id]); // serialisasi hitungan per pengguna
    const lastHour = (
      await c.query("select count(*)::int as n from game_scores where user_id = $1 and created_at > now() - interval '1 hour'", [user.id])
    ).rows[0].n;
    if (lastHour >= MAX_SCORES_PER_HOUR) return fail('too_many_requests');
    const today = (
      await c.query(
        `select coalesce(sum(xp_earned), 0)::int as n from game_scores
          where user_id = $1 and (created_at at time zone 'Asia/Jakarta')::date = (now() at time zone 'Asia/Jakarta')::date`,
        [user.id],
      )
    ).rows[0].n;
    const gain = Math.max(0, Math.min(xpRaw, DAILY_XP_CAP - today));
    await c.query(
      'insert into game_scores(user_id, score, stars, cleared, xp_earned, duration_sec) values ($1,$2,$3,$4,$5,$6)',
      [user.id, score, stars, cleared, gain, duration_sec],
    );
    const u = (await c.query('update users set xp = xp + $2 where id = $1 returning *', [user.id, gain])).rows[0];
    await c.query("insert into user_activity(user_id, activity_type) values ($1, 'game_played')", [user.id]);
    await awardBadges(c, user.id, false);
    return ok({
      score, xp_earned: gain, daily_xp_total: today + gain, daily_cap_reached: today + gain >= DAILY_XP_CAP,
      user: await userJson(c, u),
    });
  });
}

const leaderboardSchema = z.object({ limit: intQ });

export async function getLeaderboard(pool, query) {
  const p = parseInput(leaderboardSchema, query);
  if (p.error) return p.error;
  const limit = Math.min(Math.max(p.data.limit ?? 10, 1), 50);
  const r = await pool.query(
    `select row_number() over (order by sum(gs.score) desc, min(us.username)) as rank,
            min(us.username) as username, min(us.level) as level, sum(gs.score)::int as total_score
       from game_scores gs join users us on us.id = gs.user_id
      where gs.created_at > now() - interval '7 days'
      group by gs.user_id
      order by sum(gs.score) desc, min(us.username)
      limit $1`,
    [limit],
  );
  return r.rows;
}
