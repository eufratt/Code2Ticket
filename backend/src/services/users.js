import { TOKEN_RE, sha256Hex, invalidSession, forbidden } from '../lib/util.js';

export async function userJson(db, u) {
  const badges = (await db.query('select badge_code from user_badges where user_id = $1 order by earned_at, badge_code', [u.id])).rows;
  return {
    id: u.id, username: u.username, email: u.email, full_name: u.full_name, photo_url: u.photo_url,
    role: u.role, xp: u.xp, level: u.level, badges: badges.map((b) => b.badge_code), created_at: u.created_at,
  };
}

// Dasar semua endpoint bertoken (pengganti fn_require_session).
export async function sessionUser(db, token) {
  if (typeof token !== 'string' || !TOKEN_RE.test(token)) throw invalidSession();
  const hash = sha256Hex(token);
  const u = (
    await db.query(
      `select u.* from sessions s join users u on u.id = s.user_id
        where s.token_hash = $1 and s.is_valid and s.expires_at > now()`,
      [hash],
    )
  ).rows[0];
  if (!u) throw invalidSession();
  await db.query(
    `update sessions set last_seen_at = now()
      where token_hash = $1 and (last_seen_at is null or last_seen_at < now() - interval '1 minute')`,
    [hash],
  );
  return u;
}

export async function adminUser(db, token) {
  const u = await sessionUser(db, token);
  if (u.role !== 'admin') throw forbidden();
  return u;
}

// Pengganti fn_award_badges.
export async function awardBadges(client, userId, earlyBird = false) {
  const t = (await client.query('select count(*)::int as n from tickets where user_id = $1', [userId])).rows[0].n;
  const c = (await client.query('select count(*)::int as n from game_scores where user_id = $1 and cleared', [userId])).rows[0].n;
  const earned = [];
  if (t >= 1) earned.push('first_ticket');
  if (t >= 10) earned.push('ten_tickets');
  if (c >= 1) earned.push('first_maze_clear');
  if (c >= 10) earned.push('maze_master');
  if (earlyBird) earned.push('early_bird');
  for (const code of earned) {
    await client.query('insert into user_badges(user_id, badge_code) values ($1, $2) on conflict do nothing', [userId, code]);
  }
}

export const notify = (client, userId, type, title, body, giveawayId) =>
  client.query('insert into notifications(user_id, type, title, body, giveaway_id) values ($1,$2,$3,$4,$5)', [
    userId, type, title, body, giveawayId,
  ]);
