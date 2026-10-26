# Launch email waitlist

A dependency-free Cloudflare Worker serves `POST https://currency-signup.dimasike.com/api/waitlist` from `https://currency.dimasike.com` only. It stores normalized email, UTC creation time, website locale and consent version (`launch-email-v1`) in private D1. It sends no email and has no public read/export/delete endpoint. Origin validation and CORS restrict browsers; Turnstile and rate limiting also protect requests made outside browsers.

Request (`Content-Type: application/json`, maximum 4,096 UTF-8 bytes):

```json
{"email":"person@example.com","consent":true,"locale":"en-US","token":"TURNSTILE_RESPONSE"}
```

Both a new subscription and an existing email return HTTP 200 with `{"ok":true}`. Duplicates preserve the original time, locale and consent. Only the 14 locales in the website manifest are accepted. Email addresses use ASCII mailbox syntax, are trimmed/lowercased, and must fit 254 characters. Errors return `{ "ok": false, "error": "…" }`: 400 invalid request/challenge, 403 origin/preflight, 405 method, 415 content type, 429 rate limit, or 503 unavailable. Unknown paths return 404. Responses use `no-store` and `nosniff`. There is no localhost bypass.

## Verify

Node 22.13+ provides the test-only SQLite adapter; Node 26 was used during implementation. No package installation is needed:

```sh
node --test Website/waitlist-worker/test/worker.test.js
```

Tests execute the production handler and migration with real in-memory SQLite, while mocking Cloudflare's rate limiter and Turnstile transport. They do not prove deployed bindings, edge rate enforcement or real browser challenges. The injected verifier is a module-level test dependency, never a request field or runtime environment override.

## Provision and deploy

Use an existing Cloudflare account on Workers Free. From this directory, use an approved Wrangler 4.36+ installation. Keep credentials in Cloudflare's authenticated session and secret storage; never place them in source, command arguments, shell history, logs or a PR.

1. Confirm `dimasike.com` is active in Cloudflare. Use Worker `currency-launch-waitlist` with custom domain `currency-signup.dimasike.com`. This dedicated host serves `/api/waitlist`; the website stays on its existing GitHub Pages DNS configuration. Set the frontend endpoint to the full HTTPS URL above.
2. Use the existing D1 database named `currency-waitlist`; its public database identifier is configured in `wrangler.jsonc`. Keep the `DB` binding private. Apply `migrations/0001_waitlist.sql` to this database before enabling the form: `wrangler d1 migrations apply currency-waitlist --remote`.
3. Create a Turnstile widget restricted to `currency.dimasike.com`. The public sitekey belongs in the frontend. Configure its client action as `waitlist`. Store the private secret in the Worker's encrypted `TURNSTILE_SECRET` binding using the dashboard secret field or `wrangler secret put TURNSTILE_SECRET`'s interactive prompt. Never paste a secret into a command argument or transcript. Do not use Turnstile's test keys in production.
4. Use the account’s distinct rate namespace ID (config starts at `1001`). The native `WAITLIST_RATE_LIMITER` binding was successfully provisioned at 5 requests / 60 seconds on the existing Workers Free account without an upgrade. The [binding documentation](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) defines its behavior. Missing/broken bindings fail closed with 503. Do not upgrade plans or remove the check to bypass a deployment rejection.
5. Deploy with `wrangler deploy`. Keep `workers.dev` and version preview URLs disabled. Cloudflare invocation monitoring stays enabled; the handler emits no application logs. The dedicated custom domain must never fall back to a subscriber-capable origin; exhausted quotas must remain errors. Do not add request-body logging, tail sessions, log drains, public database access or a public export route.
6. Verify the real form challenge, one insertion and a duplicate in the private dashboard. Verify invalid/missing challenges never insert, wrong origins fail, GET cannot reveal records, and the native limiter can return 429. Use an owner-controlled test mailbox and remove its test row afterward. Enable the form only after these checks pass.

The binding rate is approximate and local to each Cloudflare location; it is not a global hard cap. Shared networks may share the 5/minute allowance. IP is used only as the transient native rate-limit key; it is neither sent to Siteverify nor stored in D1 or application logs. Cloudflare still processes infrastructure request metadata under its own service policies.

## Private access, CSV and deletion

Sign in to the Cloudflare dashboard → Storage & databases → D1 → `currency-waitlist` → Console/Studio. Access is governed by the Cloudflare account's permissions, never the public website.

To inspect/export, run:

```sql
SELECT email, created_at, locale, consent_version FROM waitlist ORDER BY created_at;
```

Use the dashboard's result CSV export/download control if available, confirm the exported row count, and store the file outside this repository in private storage. If the account UI lacks CSV export, do not add a public endpoint: Cloudflare officially supports [private SQL export](https://developers.cloudflare.com/d1/best-practices/import-export-data/) using authenticated Wrangler, followed by conversion in private local tooling. Imports into a spreadsheet must treat all columns as text, including email addresses, to prevent formula interpretation. Never attach exports, query results or subscriber screenshots to public issues/PRs.

For an individual withdrawal, find the exact normalized email using the private dashboard's table filter, delete that row, and confirm the filtered result is empty. Alternatively use the private console with an exact email predicate, escaping a literal apostrophe by doubling it. Do not put actual addresses in shell commands or public logs. Remove matching private CSV copies. D1 Time Travel can retain historical data; follow [Cloudflare's retention limits](https://developers.cloudflare.com/d1/platform/limits/) and do not restore deleted subscriptions.

## Retention maintenance

Follow `Documentation/PrivacyPolicy.md`: delete the launch list and private exports within 30 days after sending the manual notification. If launch is cancelled, delete each signup no later than six months after signup. No automatic cron is configured; the owner performs this maintenance in the private D1 console. Delete immediately after a completed send when practical.

Before exporting/sending, record a UTC signup cutoff privately and restrict that send to records through the cutoff. Close collection when the notice is sent. To remove the notified batch by the 30-day deadline, replace this example cutoff with that recorded timestamp, inspect the count, then run the matching deletion:

```sql
SELECT COUNT(*) FROM waitlist WHERE created_at <= '2026-10-26T12:00:00.000Z';
DELETE FROM waitlist WHERE created_at <= '2026-10-26T12:00:00.000Z';
```

If launch is cancelled, stop collection and delete the whole list promptly. When checking older signups against the six-month ceiling, the private console can select and delete overdue records with the same predicate:

```sql
SELECT COUNT(*) FROM waitlist WHERE datetime(created_at) <= datetime('now', '-6 months');
DELETE FROM waitlist WHERE datetime(created_at) <= datetime('now', '-6 months');
```

Run the matching count again to verify zero and remove private exported copies too. Do not restore removed subscriptions from historical backups. Remove the collection form and Worker route after launch/cancellation. A consent-copy change requires a new consent version. This endpoint does not send or record sent notices, so keep any send/deduplication work in a separately authorized private workflow.

## Free limits and references

As checked on 2026-10-26, [Workers Free](https://developers.cloudflare.com/workers/platform/limits/) includes 100,000 requests/day and 10 ms CPU/request. [D1 Free](https://developers.cloudflare.com/d1/platform/pricing/) includes 5 million rows read/day, 100,000 rows written/day and 5 GB total storage; index writes and administrative queries also consume quota. Exceeding D1 allowances stops operations until reset/storage cleanup. Turnstile provides a [Free plan](https://developers.cloudflare.com/turnstile/plans/) with unlimited challenges. Confirm current account entitlements before deployment; no paid upgrade is required or authorized by these instructions.

[Siteverify](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/) tokens expire after five minutes and are single use. The server checks success, hostname and action on every submission, including duplicates. A verification timeout or dependency failure leaves the database unchanged and returns a generic error. The frontend must request a fresh token for every retry.
