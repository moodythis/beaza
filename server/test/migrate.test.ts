import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker from '../src/index.ts';
import { MIGRATE_PATH, migrate } from '../src/migrate.ts';
import { Server, sealedLike, signUp, TestD1 } from './harness.ts';

test('every account, session, record and the pepper are copied unchanged', async () => {
  const old = new Server();
  const { token } = await signUp(old, 'one@example.com');
  await signUp(old, 'two@example.com');
  await old.call('POST', '/v1/records', {
    records: [
      { collection: 'txn', id: 'a1', blob: sealedLike() },
      { collection: 'txn', id: 'a2', blob: sealedLike() },
      { collection: 'settings', id: 'main', blob: sealedLike() },
    ],
  }, token);
  const fresh = new TestD1();
  const report = (await migrate({ DB: fresh, OLD_DB: old.d1 })) as Record<
    string,
    { rows: number; copied: number; same: boolean }
  >;
  assert.deepEqual(
    Object.fromEntries(Object.entries(report).map(([k, v]) => [k, [v.rows, v.copied, v.same]])),
    { users: [2, 2, true], sessions: [2, 2, true], records: [3, 3, true], meta: [1, 1, true] },
  );

  // A copied session and the pepper are really there, and the sequence
  // numbers are kept, so phones carry on from where they were.
  const user = await fresh.prepare('SELECT seq FROM users WHERE email = ?').bind('one@example.com').first<{ seq: number }>();
  assert.equal(user?.seq, 3);
  const pepper = await fresh.prepare("SELECT value FROM meta WHERE key = 'pepper'").first();
  assert.ok(pepper);
  assert.equal(
    (await fresh.prepare('SELECT COUNT(*) AS n FROM sessions').first<{ n: number }>())?.n,
    2,
  );
});

test('running it twice changes nothing', async () => {
  const old = new Server();
  await signUp(old, 'one@example.com');
  const fresh = new TestD1();
  await migrate({ DB: fresh, OLD_DB: old.d1 });
  const once = fresh.dump();
  await migrate({ DB: fresh, OLD_DB: old.d1 });
  assert.equal(fresh.dump(), once);
});

test('only the exact secret path starts it', async () => {
  const old = new Server();
  const env = { DB: new TestD1(), OLD_DB: old.d1 };
  const wrong = await worker.fetch(
    new Request('https://sync.example/__migrate/guess', { method: 'POST' }),
    env,
  );
  assert.equal(wrong.status, 404);
  const get = await worker.fetch(new Request(`https://sync.example${MIGRATE_PATH}`), env);
  assert.equal(get.status, 404);
  const ok = await worker.fetch(
    new Request(`https://sync.example${MIGRATE_PATH}`, { method: 'POST' }),
    env,
  );
  assert.equal(ok.status, 200);
});
