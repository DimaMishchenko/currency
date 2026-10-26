import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createWorker } from '../src/index.js';

const ORIGIN = 'https://currency.dimasike.com';
const valid = { email: 'person@example.com', consent: true, locale: 'en-US', token: 'challenge-token' };

function setup(options = {}) {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(new URL('../migrations/0001_waitlist.sql', import.meta.url), 'utf8'));
  const calls = { rate: [], verification: [], statements: [] };
  const env = {
    TURNSTILE_SECRET: 'test-only-secret',
    WAITLIST_RATE_LIMITER: { async limit(input) { calls.rate.push(input); return { success: options.rate ?? true }; } },
    DB: { prepare(sql) {
      calls.statements.push(sql);
      return { bind(...values) { return { async run() {
        database.prepare(sql).run(...values);
        return { success: true };
      } }; } };
    } },
  };
  const worker = createWorker({ verifyFetch: async (url, init) => {
    calls.verification.push({ url, init });
    if (options.verificationError) throw new Error('private upstream exception');
    return Response.json(options.challenge ?? { success: true, hostname: 'currency.dimasike.com', action: 'waitlist' }, { status: options.verificationStatus ?? 200 });
  } });
  const request = (body = valid, config = {}) => {
    const headers = { Origin: ORIGIN, 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1', ...config.headers };
    for (const key of Object.keys(headers)) if (headers[key] === null) delete headers[key];
    const method = config.method ?? 'POST';
    return worker.fetch(new Request(ORIGIN + (config.path ?? '/api/waitlist'), {
      method, headers,
      ...(['POST', 'PUT'].includes(method) ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    }), env);
  };
  return { database, env, calls, worker, request };
}

for (const origin of [null, 'null', 'https://other.example', 'http://localhost:8000', 'https://currency.dimasike.com.evil.example', 'http://currency.dimasike.com']) {
  test(`rejects unapproved origin ${origin}`, async () => {
    const { request, calls } = setup();
    const response = await request(valid, { headers: { Origin: origin } });
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
    assert.equal(calls.verification.length, 0);
  });
}

test('preflight allows only POST and content-type for the exact origin', async () => {
  const { request } = setup();
  const response = await request(valid, { method: 'OPTIONS', headers: { 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'content-type' } });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  assert.equal(response.headers.get('Access-Control-Allow-Methods'), 'POST');
  for (const headers of [{ 'Access-Control-Request-Method': 'GET' }, { 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization' }]) {
    assert.equal((await request(valid, { method: 'OPTIONS', headers })).status, 403);
  }
});

test('has no public read, export, or deletion API', async () => {
  const { request, calls } = setup();
  for (const method of ['GET', 'HEAD', 'DELETE', 'PUT']) assert.equal((await request(valid, { method })).status, 405);
  for (const path of ['/api/waitlist/export', '/api/waitlist/list', '/']) assert.equal((await request(valid, { method: 'GET', path })).status, 404);
  assert.equal(calls.statements.length, 0);
});

test('requires JSON and bounds both declared and streamed body bytes', async () => {
  const { request, worker, env, calls } = setup();
  assert.equal((await request(valid, { headers: { 'Content-Type': 'text/plain' } })).status, 415);
  for (const body of ['{', 'null', '[]', '"hello"', JSON.stringify({ ...valid, extra: 'x'.repeat(4096) }), JSON.stringify({ ...valid, extra: 'é'.repeat(2048) })]) {
    assert.equal((await request(body)).status, 400);
  }
  assert.equal((await request(valid, { headers: { 'Content-Length': '4097' } })).status, 400);
  const body = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(1000)); controller.enqueue(new Uint8Array(3097)); controller.close(); } });
  const streamed = new Request(ORIGIN + '/api/waitlist', { method: 'POST', headers: { Origin: ORIGIN, 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1' }, body, duplex: 'half' });
  assert.equal((await worker.fetch(streamed, env)).status, 400);
  assert.equal(calls.verification.length, 0);
});


test('accepts a maximum-length email with a maximum-length Turnstile token', async () => {
  const { request, database } = setup();
  const email = 'a'.repeat(64) + '@' + 'b'.repeat(63) + '.' + 'c'.repeat(63) + '.' + 'd'.repeat(61);
  assert.equal(email.length, 254);
  const response = await request({ ...valid, email, token: 't'.repeat(2048) });
  assert.equal(response.status, 200);
  assert.equal(database.prepare('SELECT email FROM waitlist').get().email, email);
});

for (const patch of [
  { consent: false }, { consent: 'true' }, { consent: undefined },
  { token: 't'.repeat(2049) }, { locale: 'en' }, { locale: 'xx' }, { token: '' }, { token: ' ' }, { token: undefined },
  { email: 'invalid' }, { email: 'a@b' }, { email: 'a..b@example.com' },
  { email: 'a\n@example.com' }, { email: 'x@-example.com' }, { email: 'x@example..com' },
  { email: 'a'.repeat(65) + '@example.com' }, { email: 'a'.repeat(250) + '@example.com' },
]) {
  test(`rejects invalid input ${JSON.stringify(patch)}`, async () => {
    const { request, calls } = setup();
    assert.equal((await request({ ...valid, ...patch })).status, 400);
    assert.equal(calls.verification.length, 0);
    assert.equal(calls.statements.length, 0);
  });
}

for (const challenge of [{ success: false }, { success: true, hostname: 'evil.example', action: 'waitlist' }, { success: true, hostname: 'currency.dimasike.com', action: 'login' }, { success: true, hostname: 'currency.dimasike.com' }, { success: 'true', hostname: 'currency.dimasike.com', action: 'waitlist' }]) {
  test(`requires successful challenge with exact hostname and action ${JSON.stringify(challenge)}`, async () => {
    const { request, calls } = setup({ challenge });
    assert.equal((await request()).status, 400);
    assert.equal(calls.statements.length, 0);
  });
}

test('stores only normalized email, creation time, locale and consent version; deduplicates without changing the response or original record', async () => {
  const { request, database, calls } = setup();
  const first = await request({ ...valid, email: ' Person@Example.com ', ip: 'not-stored', unrelated: 'not-stored' });
  const before = database.prepare('SELECT * FROM waitlist').get();
  const second = await request({ ...valid, email: 'PERSON@EXAMPLE.COM', locale: 'de-DE' });
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.deepEqual(await first.json(), { ok: true });
  assert.deepEqual(await second.json(), { ok: true });
  assert.deepEqual(database.prepare('SELECT * FROM waitlist').get(), before);
  assert.equal(database.prepare('SELECT COUNT(*) AS count FROM waitlist').get().count, 1);
  assert.deepEqual(Object.keys(before), ['email', 'created_at', 'locale', 'consent_version']);
  assert.equal(before.email, 'person@example.com');
  assert.equal(before.locale, 'en-US');
  assert.equal(before.consent_version, 'launch-email-v1');
  assert.ok(Number.isFinite(Date.parse(before.created_at)));
  assert.equal(calls.verification.length, 2);
  const { url, init } = calls.verification[0];
  assert.equal(url, 'https://challenges.cloudflare.com/turnstile/v0/siteverify');
  assert.equal(init.body.get('secret'), 'test-only-secret');
  assert.equal(init.body.get('response'), valid.token);
  assert.equal(init.body.has('remoteip'), false);
  assert.ok(init.signal instanceof AbortSignal);
  assert.equal(first.headers.get('Cache-Control'), 'no-store');
  assert.equal(first.headers.get('X-Content-Type-Options'), 'nosniff');
});

test('all website locales are accepted and stay in sync with the manifest', async () => {
  const { request } = setup();
  const locales = JSON.parse(readFileSync(new URL('../../locales/manifest.json', import.meta.url), 'utf8'));
  assert.equal(locales.length, 14);
  for (const { locale } of locales) assert.equal((await request({ ...valid, locale })).status, 200);
});

test('binds email as data even with SQL metacharacters', async () => {
  const { request, database, calls } = setup();
  const email = "x'--@example.com";
  assert.equal((await request({ ...valid, email })).status, 200);
  assert.equal(database.prepare('SELECT email FROM waitlist').get().email, email);
  assert.ok(calls.statements[0].includes('VALUES (?, ?, ?, ?)'));
  assert.ok(!calls.statements[0].includes(email));
});

test('rate limit uses Cloudflare IP only and blocks before upstream calls', async () => {
  const { request, calls } = setup({ rate: false });
  const response = await request(valid, { headers: { 'X-Forwarded-For': 'spoofed' } });
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('Retry-After'), '60');
  assert.deepEqual(calls.rate, [{ key: '192.0.2.1' }]);
  assert.equal(calls.verification.length, 0);
});

test('missing private bindings or IP fail closed', async () => {
  for (const binding of ['DB', 'TURNSTILE_SECRET', 'WAITLIST_RATE_LIMITER']) {
    const { env, request, calls } = setup();
    delete env[binding];
    assert.equal((await request()).status, 503);
    assert.equal(calls.statements.length, 0);
  }
  assert.equal((await setup().request(valid, { headers: { 'CF-Connecting-IP': null } })).status, 503);
});

test('upstream, limiter and database errors stay generic and fail closed', async () => {
  for (const options of [{ verificationError: true }, { verificationStatus: 503 }]) {
    const { request, calls } = setup(options);
    const response = await request();
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { ok: false, error: 'unavailable' });
    assert.equal(calls.statements.length, 0);
  }
  for (const binding of ['WAITLIST_RATE_LIMITER', 'DB']) {
    const { env, request } = setup();
    env[binding] = binding === 'DB' ? { prepare() { throw new Error('private DB info'); } } : { async limit() { throw new Error('private limiter info'); } };
    const response = await request();
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { ok: false, error: 'unavailable' });
  }
});
