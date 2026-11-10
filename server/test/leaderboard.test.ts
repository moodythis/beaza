import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { BOARD_CONSENT_VERSION, BOARD_SIZE, checkNickname, fnv1a, personaNumber } from '../src/leaderboard.ts';
import { Server } from './harness.ts';

const id = (n: number) => n.toString(16).padStart(32, '0');

const entry = (n: number, extra: Record<string, unknown> = {}) => ({
  consent: BOARD_CONSENT_VERSION,
  boardId: id(n),
  displayMode: 'persona',
  points30d: 100,
  streakDays: 3,
  ...extra,
});

describe('the leaderboard', () => {
  it('ranks by points, then streak, and marks only the caller', async () => {
    const s = new Server();
    await s.call('POST', '/v1/leaderboard', entry(1, { points30d: 200, streakDays: 2 }));
    await s.call('POST', '/v1/leaderboard', entry(2, { points30d: 200, streakDays: 9 }));
    const res = await s.call('POST', '/v1/leaderboard', entry(3, { displayMode: 'nickname', nickname: '  نوخذة   البحر ', points30d: 50 }));
    assert.equal(res.status, 200);
    assert.equal(res.body.rank, 3);
    assert.deepEqual(res.body.rows.map((r: any) => [r.rank, r.points, r.streak, r.me ?? false]), [
      [1, 200, 9, false],
      [2, 200, 2, false],
      [3, 50, 3, true],
    ]);
    assert.equal(res.body.rows[2].nickname, 'نوخذة البحر');
    assert.equal(res.body.rows[0].nickname, undefined);
    assert.equal(res.body.rows[0].number, personaNumber(id(2)));
    // Anyone can read it; nobody is marked and no id is in it.
    const open = await s.call('GET', '/v1/leaderboard');
    assert.equal(open.body.rows.length, 3);
    assert.equal(JSON.stringify(open.body).includes('"me"'), false);
    assert.deepEqual(Object.keys(open.body.rows[0]).sort(), ['number', 'points', 'rank', 'streak']);
  });

  it('updates a row in place and stores nothing that points to a person', async () => {
    const s = new Server();
    await s.call('POST', '/v1/leaderboard', entry(7, { points30d: 10 }));
    const res = await s.call('POST', '/v1/leaderboard', entry(7, { points30d: 120, streakDays: 5 }), undefined, '198.51.100.9');
    assert.equal(res.body.rows.length, 1);
    assert.equal(res.body.rows[0].points, 120);
    const stored = JSON.stringify(s.d1.db.prepare('SELECT * FROM leaderboard').all());
    assert.equal(stored.includes(id(7)), false, 'the id is kept only as a hash');
    assert.equal(stored.includes('198.51.100.9'), false);
    assert.equal(stored.includes('203.0.113.7'), false);
    assert.deepEqual(
      Object.keys(s.d1.db.prepare('SELECT * FROM leaderboard').get() as object).sort(),
      ['id_hash', 'nickname', 'number', 'points', 'streak', 'updated_day'],
    );
  });

  it('keeps the top 50 only; a lower score gets no rank and is not kept', async () => {
    const s = new Server();
    for (let i = 1; i <= BOARD_SIZE; i++) {
      await s.call('POST', '/v1/leaderboard', entry(i, { points30d: 100 + i }));
    }
    const low = await s.call('POST', '/v1/leaderboard', entry(900, { points30d: 5 }));
    assert.equal(low.body.rank, null);
    assert.equal(low.body.rows.length, BOARD_SIZE);
    const high = await s.call('POST', '/v1/leaderboard', entry(901, { points30d: 4000 }));
    assert.equal(high.body.rank, 1);
    assert.equal(high.body.rows.length, BOARD_SIZE);
    assert.equal((s.d1.db.prepare('SELECT COUNT(*) AS n FROM leaderboard').get() as any).n, BOARD_SIZE);
  });

  it('a nickname is letters and spaces only: no digits in any script, no @', async () => {
    const s = new Server();
    for (const bad of ['ali99', 'علي٣٣', 'a@b', '39001234', 'ab', 'x'.repeat(16), 'ali.k', 'ali_k', 'ali-k', '', '   ', 'عمر 😀']) {
      const res = await s.call('POST', '/v1/leaderboard', entry(1, { displayMode: 'nickname', nickname: bad }));
      assert.equal(res.status, 400, bad);
      assert.equal(res.body.error, 'bad_nickname', bad);
    }
    assert.equal(checkNickname('Abu  Salman'), 'Abu Salman');
    assert.equal(checkNickname('أبو سلمان'), 'أبو سلمان');
    // A persona row may not carry a name, and a nickname row must.
    assert.equal((await s.call('POST', '/v1/leaderboard', entry(1, { nickname: 'Salman' }))).body.error, 'bad_display_mode');
    assert.equal((await s.call('POST', '/v1/leaderboard', entry(1, { displayMode: 'nickname' }))).body.error, 'bad_nickname');
    assert.equal((s.d1.db.prepare('SELECT COUNT(*) AS n FROM leaderboard').get() as any).n, 0);
  });

  it('refuses anything else: other fields, money, bad numbers, no consent', async () => {
    const s = new Server();
    const bad = async (extra: Record<string, unknown>) => (await s.call('POST', '/v1/leaderboard', entry(1, extra))).body.error;
    assert.equal(await bad({ email: 'a@b.c' }), 'unexpected_field');
    assert.equal(await bad({ amountFils: 5000 }), 'unexpected_field');
    assert.equal(await bad({ points30d: 1.5 }), 'bad_points');
    assert.equal(await bad({ points30d: -1 }), 'bad_points');
    assert.equal(await bad({ points30d: 5001 }), 'bad_points');
    assert.equal(await bad({ streakDays: 366 }), 'bad_streak');
    assert.equal(await bad({ boardId: 'user@example.com' }), 'bad_board_id');
    assert.equal(await bad({ consent: '2020-01-01' }), 'consent_required');
  });

  it('leaving deletes the row; old rows drop after 30 days', async () => {
    const s = new Server();
    await s.call('POST', '/v1/leaderboard', entry(1));
    await s.call('POST', '/v1/leaderboard', entry(2));
    assert.equal((await s.call('POST', '/v1/leaderboard/leave', { boardId: id(1) })).body.ok, true);
    assert.equal((await s.call('GET', '/v1/leaderboard')).body.rows.length, 1);
    s.advance(31 * 24 * 60 * 60 * 1000);
    const res = await s.call('POST', '/v1/leaderboard', entry(3));
    assert.equal(res.body.rows.length, 1);
    assert.equal(res.body.rank, 1);
  });

  it('the persona number matches the phone (FNV-1a)', () => {
    assert.equal(fnv1a(''), 0x811c9dc5);
    // Known vector for the two-bytes-per-unit variant, checked against the Dart code's own test.
    assert.equal(personaNumber('00000000000000000000000000000001') >= 100, true);
    assert.equal(personaNumber('00000000000000000000000000000001') <= 999, true);
    assert.equal(personaNumber('abc'), 100 + (fnv1a('abc') % 900));
    // The same two values are pinned in the app's leaderboard_test.dart.
    assert.equal(fnv1a('abc'), 2921240957);
    assert.equal(personaNumber('0123456789abcdef0123456789abcdef'), 413);
  });
});
