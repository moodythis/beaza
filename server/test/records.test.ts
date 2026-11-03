import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { randomBytes, toB64 } from '../src/util.ts';
import { newAccountFields, sealedLike, Server, signUp } from './harness.ts';

const rec = (id: string, collection = 'transactions', blob = sealedLike()) => ({ collection, id, blob });

describe('push and pull', () => {
  it('a record comes back exactly as sent, with a seq number', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const r = rec('a1');
    const push = await s.call('POST', '/v1/records', { records: [r] }, token);
    assert.equal(push.status, 200);
    assert.equal(push.body.seq, 1);

    const pull = await s.call('GET', '/v1/records?since=0', undefined, token);
    assert.deepEqual(pull.body.records, [{ ...r, seq: 1 }]);
    assert.equal(pull.body.nextSince, 1);
    assert.equal(pull.body.more, false);
  });

  it('a second phone pulls what the first pushed', async () => {
    const s = new Server();
    const { account, token } = await signUp(s);
    await s.call('POST', '/v1/records', { records: [rec('a1'), rec('a2', 'settings')] }, token);
    const phoneB = (await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).body.token;
    const pull = await s.call('GET', '/v1/records', undefined, phoneB);
    assert.equal(pull.body.records.length, 2);
  });

  it('seq numbers keep growing, and "since" returns only newer changes', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    await s.call('POST', '/v1/records', { records: [rec('a1'), rec('a2'), rec('a3')] }, token);
    const second = await s.call('POST', '/v1/records', { records: [rec('a4')] }, token);
    assert.equal(second.body.seq, 4);

    const pull = await s.call('GET', '/v1/records?since=3', undefined, token);
    assert.deepEqual(pull.body.records.map((r: any) => [r.id, r.seq]), [['a4', 4]]);
    const none = await s.call('GET', '/v1/records?since=4', undefined, token);
    assert.deepEqual(none.body.records, []);
    assert.equal(none.body.nextSince, 4);
  });

  it('a pull reports the latest change number, so a phone can tell the server lost changes', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const empty = await s.call('GET', '/v1/records?since=0', undefined, token);
    assert.equal(empty.body.latest, 0);
    await s.call('POST', '/v1/records', { records: [rec('a1'), rec('a2')] }, token);
    const first = await s.call('GET', '/v1/records?since=0&limit=1', undefined, token);
    assert.equal(first.body.nextSince, 1);
    assert.equal(first.body.latest, 2);
    // A phone that already pulled up to 9 sees the server is behind it.
    const ahead = await s.call('GET', '/v1/records?since=9', undefined, token);
    assert.equal(ahead.body.latest, 2);
    assert.ok(ahead.body.latest < 9);
  });

  it('changing a record gives it a new seq, so other phones see the change', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    await s.call('POST', '/v1/records', { records: [rec('a1'), rec('a2')] }, token);
    const changed = sealedLike(300);
    await s.call('POST', '/v1/records', { records: [rec('a1', 'transactions', changed)] }, token);

    const pull = await s.call('GET', '/v1/records?since=2', undefined, token);
    assert.equal(pull.body.records.length, 1);
    assert.equal(pull.body.records[0].blob, changed);
    assert.equal(pull.body.records[0].seq, 3);
    const all = await s.call('GET', '/v1/records', undefined, token);
    assert.equal(all.body.records.length, 2, 'still two records, not three');
  });

  it('the same id in one push: the last one wins', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const last = sealedLike(200);
    await s.call('POST', '/v1/records', { records: [rec('a1'), rec('a1', 'transactions', last)] }, token);
    const pull = await s.call('GET', '/v1/records', undefined, token);
    assert.equal(pull.body.records.length, 1);
    assert.equal(pull.body.records[0].blob, last);
  });

  it('pages through a long list with the limit', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const records = Array.from({ length: 7 }, (_, i) => rec(`r${i}`));
    await s.call('POST', '/v1/records', { records }, token);

    const seen: string[] = [];
    let since = 0;
    for (let page = 0; page < 10; page++) {
      const res = await s.call('GET', `/v1/records?since=${since}&limit=3`, undefined, token);
      seen.push(...res.body.records.map((r: any) => r.id));
      since = res.body.nextSince;
      if (!res.body.more) break;
    }
    assert.deepEqual(seen, records.map((r) => r.id));
  });
});

describe('every account is separate', () => {
  it('one account never sees or changes another account\'s records', async () => {
    const s = new Server();
    const a = await signUp(s, 'a@example.com');
    const b = await signUp(s, 'b@example.com');
    await s.call('POST', '/v1/records', { records: [rec('same-id', 'transactions', sealedLike(111))] }, a.token);
    const bBlob = sealedLike(222);
    await s.call('POST', '/v1/records', { records: [rec('same-id', 'transactions', bBlob)] }, b.token);

    const fromA = await s.call('GET', '/v1/records', undefined, a.token);
    const fromB = await s.call('GET', '/v1/records', undefined, b.token);
    assert.equal(fromA.body.records.length, 1);
    assert.notEqual(fromA.body.records[0].blob, bBlob);
    assert.equal(fromB.body.records.length, 1);
    assert.equal(fromB.body.records[0].blob, bBlob);
    assert.equal(fromB.body.records[0].seq, 1, 'each account counts its own seq');
  });

  it('deleting one account leaves the other\'s records', async () => {
    const s = new Server();
    const a = await signUp(s, 'a@example.com');
    const b = await signUp(s, 'b@example.com');
    await s.call('POST', '/v1/records', { records: [rec('x1')] }, a.token);
    await s.call('POST', '/v1/records', { records: [rec('x1')] }, b.token);
    await s.call('POST', '/v1/account/delete', { authKey: a.account.authKey }, a.token);
    const left = await s.call('GET', '/v1/records', undefined, b.token);
    assert.equal(left.body.records.length, 1);
  });
});

describe('what the server accepts', () => {
  it('needs a session', async () => {
    const s = new Server();
    assert.equal((await s.call('POST', '/v1/records', { records: [rec('a1')] })).status, 401);
    assert.equal((await s.call('GET', '/v1/records')).status, 401);
  });

  it('refuses malformed records and changes nothing', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const tooMany = Array.from({ length: 101 }, (_, i) => rec(`r${i}`));
    const cases: unknown[] = [
      [],
      tooMany,
      [rec('a1', 'Transactions')],
      [rec('a1', 'a/b')],
      [rec('a/1')],
      [rec('')],
      [rec('a1', 'transactions', 'not base64!')],
      [rec('a1', 'transactions', toB64(randomBytes(20)))],
      [rec('a1', 'transactions', 'A'.repeat(20_000))],
      [{ collection: 'transactions', id: 'a1' }],
      ['text'],
    ];
    for (const records of cases) {
      const res = await s.call('POST', '/v1/records', { records }, token);
      assert.equal(res.status, 400, JSON.stringify(records).slice(0, 60));
      assert.equal(res.body.error, 'bad_records');
    }
    // One bad record spoils the whole push (nothing half-saved).
    const mixed = await s.call('POST', '/v1/records', { records: [rec('good'), rec('bad', 'No')] }, token);
    assert.equal(mixed.status, 400);
    assert.deepEqual((await s.call('GET', '/v1/records', undefined, token)).body.records, []);
  });

  it('refuses bad query values', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    for (const q of ['since=-1', 'since=abc', 'limit=0', 'since=1.5']) {
      assert.equal((await s.call('GET', `/v1/records?${q}`, undefined, token)).status, 400, q);
    }
  });
});

describe('what is stored', () => {
  it('holds hashes only: no key, no token, no password; the blob is kept as sent', async () => {
    const s = new Server();
    const account = newAccountFields('person@example.com');
    const signup = await s.call('POST', '/v1/register', account);
    const token = signup.body.token as string;
    const blob = sealedLike(333);
    await s.call('POST', '/v1/records', { records: [rec('a1', 'transactions', blob)] }, token);
    await s.call('POST', '/v1/login', { email: account.email, authKey: toB64(randomBytes(32)) });

    const stored = s.d1.dump();
    assert.ok(stored.includes(blob), 'the blob is stored as sent');
    assert.equal(stored.includes(account.authKey), false);
    assert.equal(stored.includes(account.recoveryAuthKey), false);
    assert.equal(stored.includes(token), false);
    // The only readable personal data is the email, which sign-in needs.
    assert.ok(stored.includes('person@example.com'));
    // Address of the caller is not stored anywhere.
    assert.equal(stored.includes('203.0.113.7'), false);
  });

  it('the attempts table holds no email and no address', async () => {
    const s = new Server();
    await s.call('POST', '/v1/login', { email: 'victim@example.com', authKey: toB64(randomBytes(32)) });
    const rows = JSON.stringify(s.d1.db.prepare('SELECT * FROM attempts').all());
    assert.ok(rows.length > 10);
    assert.equal(rows.includes('victim'), false);
    assert.equal(rows.includes('203.0.113.7'), false);
  });

  it('the request log has the route and status only', async () => {
    const s = new Server();
    const lines: string[] = [];
    const { handle } = await import('../src/app.ts');
    const account = newAccountFields('private@example.com');
    await handle(
      new Request('https://sync.example/v1/register', { method: 'POST', body: JSON.stringify(account) }),
      { DB: s.d1 },
      { now: () => s.time, log: (line) => lines.push(line) },
    );
    assert.deepEqual(lines, ['{"route":"POST /v1/register","status":200}']);
  });
});
