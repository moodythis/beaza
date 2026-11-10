// The optional leaderboard: points and streak days only, never money.
//
// A phone joins with a separate consent and sends a random id it made up
// (linked to no account), how it wants to be shown, its points of the last
// 30 days and its streak. The server keeps the 50 best rows and nothing
// else: no account, no e-mail, no IP address, no amount, no shop.
import type { D1Like } from './d1.ts';
import { sha256, toHex, utf8 } from './util.ts';
import { HttpError } from './validate.ts';

/** The consent the phone must hold (app: kBoardConsentVersion). */
export const BOARD_CONSENT_VERSION = '2026-11-10.1';

/** Rows kept. */
export const BOARD_SIZE = 50;

/** Updates a day, for everyone together. */
export const BOARD_DAILY_CAP = 20_000;

/** A row not updated for this many days is dropped: its points are about
 * the last 30 days, so it would be stale. */
export const BOARD_STALE_DAYS = 30;

export const MAX_POINTS = 5000;
export const MAX_STREAK = 365;

const FIELDS = ['consent', 'boardId', 'displayMode', 'nickname', 'points30d', 'streakDays'];

/** FNV-1a over UTF-16 code units, as the phone computes it (app:
 * fnv1a in leaderboard.dart). */
export function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    const u = s.charCodeAt(i);
    h ^= u & 0xff;
    h = Math.imul(h, 0x01000193) >>> 0;
    h ^= u >> 8;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** The persona number, 100 to 999. */
export const personaNumber = (boardId: string) => 100 + (fnv1a(boardId) % 900);

/** A nickname is 3 to 15 letters and spaces, nothing else: no digit in any
 * script, no @, dot or dash, so no phone number, CPR number, e-mail address
 * or handle fits. Returns it tidied, or throws. */
export function checkNickname(v: unknown): string {
  if (typeof v !== 'string') throw new HttpError(400, 'bad_nickname');
  const n = v.trim().replace(/\s+/gu, ' ');
  const length = [...n].length;
  if (length < 3 || length > 15 || !/^[\p{L}\p{M} ]+$/u.test(n)) {
    throw new HttpError(400, 'bad_nickname');
  }
  return n;
}

export function checkBoardId(v: unknown): string {
  if (typeof v !== 'string' || !/^[0-9a-f]{32}$/.test(v)) throw new HttpError(400, 'bad_board_id');
  return v;
}

function int(v: unknown, max: number, code: string): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > max) throw new HttpError(400, code);
  return v;
}

export type BoardInput = { boardId: string; nickname: string | null; points: number; streak: number };

export function checkBoardInput(body: Record<string, unknown>): BoardInput {
  for (const k of Object.keys(body)) {
    if (!FIELDS.includes(k)) throw new HttpError(400, 'unexpected_field', { field: k });
  }
  if (body.consent !== BOARD_CONSENT_VERSION) {
    throw new HttpError(400, 'consent_required', { version: BOARD_CONSENT_VERSION });
  }
  const boardId = checkBoardId(body.boardId);
  let nickname: string | null = null;
  if (body.displayMode === 'nickname') {
    nickname = checkNickname(body.nickname);
  } else if (body.displayMode !== 'persona' || body.nickname !== undefined) {
    // A persona row carries no name at all.
    throw new HttpError(400, 'bad_display_mode');
  }
  return {
    boardId,
    nickname,
    points: int(body.points30d, MAX_POINTS, 'bad_points'),
    streak: int(body.streakDays, MAX_STREAK, 'bad_streak'),
  };
}

const dayOf = (ms: number) => new Date(ms).toISOString().slice(0, 10);

const hashOf = async (boardId: string) => toHex(await sha256(utf8(boardId)));

type Row = { id_hash: string; number: number; nickname: string | null; points: number; streak: number };

const ORDER = 'ORDER BY points DESC, streak DESC, number ASC, id_hash ASC';

async function rows(db: D1Like): Promise<Row[]> {
  const r = await db
    .prepare(`SELECT id_hash, number, nickname, points, streak FROM leaderboard ${ORDER} LIMIT ${BOARD_SIZE}`)
    .all<Row>();
  return r.results;
}

function shape(list: Row[], mine?: string) {
  return list.map((r, i) => ({
    rank: i + 1,
    points: r.points,
    streak: r.streak,
    number: r.number,
    ...(r.nickname === null ? {} : { nickname: r.nickname }),
    ...(mine !== undefined && r.id_hash === mine ? { me: true } : {}),
  }));
}

/** GET: the board as anyone may see it. */
export async function readBoard(db: D1Like): Promise<Record<string, unknown>> {
  return { rows: shape(await rows(db)) };
}

/** POST: puts this phone's score on the board and returns the board with
 * its row marked. `rank` is null when the score is outside the top 50 (the
 * row is then not kept). */
export async function postBoard(
  body: Record<string, unknown>,
  db: D1Like,
  now: number,
  cap = BOARD_DAILY_CAP,
): Promise<Record<string, unknown>> {
  const x = checkBoardInput(body);
  const today = dayOf(now);
  const used = await db
    .prepare(
      'INSERT INTO leaderboard_usage (day, count) VALUES (?, 1) ' +
        'ON CONFLICT (day) DO UPDATE SET count = count + 1 RETURNING count',
    )
    .bind(today)
    .first<{ count: number }>();
  if ((used?.count ?? 0) > cap) throw new HttpError(429, 'board_busy');
  const id = await hashOf(x.boardId);
  await db
    .prepare(
      'INSERT INTO leaderboard (id_hash, number, nickname, points, streak, updated_day) VALUES (?, ?, ?, ?, ?, ?) ' +
        'ON CONFLICT (id_hash) DO UPDATE SET nickname = excluded.nickname, points = excluded.points, ' +
        'streak = excluded.streak, updated_day = excluded.updated_day',
    )
    .bind(id, personaNumber(x.boardId), x.nickname, x.points, x.streak, today)
    .run();
  await db
    .prepare('DELETE FROM leaderboard WHERE updated_day < ?')
    .bind(dayOf(now - BOARD_STALE_DAYS * 24 * 60 * 60 * 1000))
    .run();
  await db
    .prepare(
      `DELETE FROM leaderboard WHERE id_hash NOT IN (SELECT id_hash FROM leaderboard ${ORDER} LIMIT ${BOARD_SIZE})`,
    )
    .run();
  const list = await rows(db);
  const at = list.findIndex((r) => r.id_hash === id);
  return { rows: shape(list, id), rank: at < 0 ? null : at + 1 };
}

/** Leaving: the row is deleted at once. */
export async function leaveBoard(body: Record<string, unknown>, db: D1Like): Promise<Record<string, unknown>> {
  for (const k of Object.keys(body)) {
    if (k !== 'boardId') throw new HttpError(400, 'unexpected_field', { field: k });
  }
  const id = await hashOf(checkBoardId(body.boardId));
  await db.prepare('DELETE FROM leaderboard WHERE id_hash = ?').bind(id).run();
  return { ok: true };
}
