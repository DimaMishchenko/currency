const ORIGIN = 'https://currency.dimasike.com';
const HOSTNAME = 'currency.dimasike.com';
const MAX_BODY_BYTES = 4096;
const CONSENT_VERSION = 'launch-email-v1';
const LOCALES = new Set(['en-US', 'de-DE', 'fr-FR', 'es-ES', 'it', 'pt-BR', 'ja', 'ko', 'tr', 'ru', 'uk', 'zh-Hans', 'zh-Hant', 'et']);
const INSERT = 'INSERT INTO waitlist (email, created_at, locale, consent_version) VALUES (?, ?, ?, ?) ON CONFLICT(email) DO NOTHING';

function reply(status, error, originAllowed, extraHeaders = {}) {
  return new Response(JSON.stringify(error ? { ok: false, error } : { ok: true }), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      Vary: 'Origin',
      ...(originAllowed ? { 'Access-Control-Allow-Origin': ORIGIN } : {}),
      ...extraHeaders,
    },
  });
}

async function readBody(request) {
  const length = request.headers.get('Content-Length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > MAX_BODY_BYTES)) throw new Error();
  if (!request.body) throw new Error();
  const reader = request.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  let bytes = 0;
  let body = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) throw new Error();
      body += decoder.decode(value, { stream: true });
    }
    return JSON.parse(body + decoder.decode());
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function validatedEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[a-z0-9!#$%&'*+\-/=?^_`{|}~.]+@[a-z0-9.-]+\.[a-z]{2,63}$/.test(email)) return null;
  const [local, domain] = email.split('@');
  if (local.length > 64 || local.startsWith('.') || local.endsWith('.') || local.includes('..')) return null;
  if (domain.split('.').some(label => !label.length || label.length > 63 || label.startsWith('-') || label.endsWith('-'))) return null;
  return email;
}

export function createWorker({ verifyFetch = globalThis.fetch } = {}) {
  return {
    async fetch(request, env) {
      const originAllowed = request.headers.get('Origin') === ORIGIN;
      if (new URL(request.url).pathname !== '/api/waitlist') return reply(404, 'not_found', originAllowed);
      if (!originAllowed) return reply(403, 'forbidden', false);
      if (request.method === 'OPTIONS') {
        const headers = (request.headers.get('Access-Control-Request-Headers') || '').toLowerCase().split(',').map(value => value.trim()).filter(Boolean);
        if (request.headers.get('Access-Control-Request-Method') !== 'POST' || headers.some(value => value !== 'content-type')) return reply(403, 'forbidden', true);
        return new Response(null, { status: 204, headers: {
          'Access-Control-Allow-Origin': ORIGIN,
          'Access-Control-Allow-Methods': 'POST',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff',
          Vary: 'Origin',
        } });
      }
      if (request.method !== 'POST') return reply(405, 'method_not_allowed', true, { Allow: 'POST, OPTIONS' });
      if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return reply(415, 'invalid_request', true);
      try {
        if (!env.DB || !env.TURNSTILE_SECRET || !env.WAITLIST_RATE_LIMITER) return reply(503, 'unavailable', true);
        const ip = request.headers.get('CF-Connecting-IP');
        if (!ip) return reply(503, 'unavailable', true);
        const rate = await env.WAITLIST_RATE_LIMITER.limit({ key: ip });
        if (rate.success !== true) return reply(429, 'rate_limited', true, { 'Retry-After': '60' });
        let data;
        try {
          data = await readBody(request);
        } catch {
          return reply(400, 'invalid_request', true);
        }
        if (!data || typeof data !== 'object' || Array.isArray(data)) return reply(400, 'invalid_request', true);
        const email = validatedEmail(data.email);
        if (!email || data.consent !== true || !LOCALES.has(data.locale) || typeof data.token !== 'string' || !data.token.trim() || data.token.length > 2048) return reply(400, 'invalid_request', true);
        const verification = await verifyFetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
          method: 'POST',
          body: new URLSearchParams({ secret: env.TURNSTILE_SECRET, response: data.token }),
          signal: AbortSignal.timeout(8000),
        });
        if (!verification.ok) return reply(503, 'unavailable', true);
        const challenge = await verification.json();
        if (challenge.success !== true || challenge.hostname !== HOSTNAME || challenge.action !== 'waitlist') return reply(400, 'verification_failed', true);
        const result = await env.DB.prepare(INSERT).bind(email, new Date().toISOString(), data.locale, CONSENT_VERSION).run();
        if (result.success !== true) return reply(503, 'unavailable', true);
        return reply(200, null, true);
      } catch {
        return reply(503, 'unavailable', true);
      }
    },
  };
}

export default createWorker();
