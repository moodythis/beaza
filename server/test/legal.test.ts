import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { handle } from '../src/app.ts';
import { PRIVACY_VERSION, TERMS_VERSION } from '../src/legal.ts';
import { newAccountFields, sealedLike, Server, signUp } from './harness.ts';

const current = { privacy: PRIVACY_VERSION, terms: TERMS_VERSION, adult: true };

describe('consent at sign-up (GDPR Art. 7, Bahrain PDPL)', () => {
  it('is required', async () => {
    const s = new Server();
    const { consent: _, ...withoutConsent } = newAccountFields();
    const res = await s.call('POST', '/v1/register', withoutConsent);
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'consent_required');
  });

  it('privacy, terms and age are each needed on their own', async () => {
    const s = new Server();
    const fields = newAccountFields();
    const missing = [
      { terms: TERMS_VERSION, adult: true },
      { privacy: PRIVACY_VERSION, adult: true },
      { privacy: PRIVACY_VERSION, terms: TERMS_VERSION },
      { ...current, adult: false },
      { ...current, adult: 'yes' },
    ];
    for (const consent of missing) {
      const res = await s.call('POST', '/v1/register', { ...fields, consent });
      assert.equal(res.body.error, 'consent_required', JSON.stringify(consent));
    }
  });

  it('must be to the current versions, or the app is told the new ones', async () => {
    const s = new Server();
    for (const consent of [
      { ...current, privacy: '2020-01-01' },
      { ...current, terms: '2020-01-01' },
    ]) {
      const res = await s.call('POST', '/v1/register', { ...newAccountFields(), consent });
      assert.equal(res.status, 400);
      assert.equal(res.body.error, 'documents_outdated');
      assert.deepEqual(
        { privacy: res.body.privacy, terms: res.body.terms },
        { privacy: PRIVACY_VERSION, terms: TERMS_VERSION },
      );
    }
  });

  it('is recorded with both versions and the server time', async () => {
    const s = new Server();
    await signUp(s);
    const row = s.d1.db
      .prepare('SELECT privacy_version, terms_version, consent_at FROM users')
      .get() as { privacy_version: string; terms_version: string; consent_at: number };
    assert.equal(row.privacy_version, PRIVACY_VERSION);
    assert.equal(row.terms_version, TERMS_VERSION);
    assert.equal(row.consent_at, s.time);
  });
});

describe('right of access (GDPR Art. 15)', () => {
  it('shows what the server holds about the account', async () => {
    const s = new Server();
    const { token } = await signUp(s, 'me@example.com');
    await s.call(
      'POST',
      '/v1/records',
      { records: [{ collection: 'transactions', id: 'a', blob: sealedLike() }] },
      token,
    );
    const res = await s.call('GET', '/v1/account', undefined, token);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      email: 'me@example.com',
      createdAt: s.time,
      consent: { privacy: PRIVACY_VERSION, terms: TERMS_VERSION, at: s.time },
      encryptedRecords: 1,
      activeSessions: 1,
      current: { privacy: PRIVACY_VERSION, terms: TERMS_VERSION },
    });
  });

  it('needs a session', async () => {
    const s = new Server();
    await signUp(s);
    assert.equal((await s.call('GET', '/v1/account')).status, 401);
  });
});

describe('public pages', () => {
  async function page(path: string, contact?: string) {
    const s = new Server();
    const res = await handle(
      new Request(`https://sync.example${path}`),
      { DB: s.d1, PRIVACY_CONTACT: contact },
      { now: () => s.time, log: () => {} },
    );
    return { res, html: await res.text() };
  }

  it('privacy notice: HTML in Arabic and English with the version', async () => {
    const { res, html } = await page('/privacy');
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') ?? '', /text\/html/);
    assert.ok(html.includes('إشعار الخصوصية'));
    assert.ok(html.includes('Beaza privacy notice'));
    assert.ok(html.includes(`Version ${PRIVACY_VERSION}`));
    assert.ok(html.includes('dir="rtl"'));
    assert.ok(html.includes('href="/terms"'));
  });

  it('terms of use: HTML in Arabic and English, Bahraini law', async () => {
    const { res, html } = await page('/terms');
    assert.equal(res.status, 200);
    assert.ok(html.includes('شروط استخدام بيزة'));
    assert.ok(html.includes('Beaza terms of use'));
    assert.ok(html.includes('Kingdom of Bahrain'));
    assert.ok(html.includes(`Version ${TERMS_VERSION}`));
    assert.ok(html.includes('href="/privacy"'));
  });

  it('run no scripts and load nothing from elsewhere', async () => {
    for (const path of ['/privacy', '/terms']) {
      const { res, html } = await page(path);
      assert.equal(html.includes('<script'), false);
      assert.match(res.headers.get('content-security-policy') ?? '', /default-src 'none'/);
    }
  });

  it('show the contact only when one is set, escaped', async () => {
    assert.equal((await page('/privacy')).html.includes('Contact:'), false);
    const { html } = await page('/privacy', 'privacy@example.com <x>');
    assert.ok(html.includes('privacy@example.com &lt;x&gt;'));
  });
});
