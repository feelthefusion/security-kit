---
name: data-exposure
description: "Use when anything could make private data publicly reachable: public bucket, CDN, static folder, uploads route, backup in public, database dump or export in a bucket, PII leak, signed URL, source maps, .env/.git exposure, directory listing, verbose errors, or a data exposure audit. Owns the rule 'nothing sensitive is ever publicly reachable': the write rules, the AUDIT procedure (public bucket inventory, unauthenticated endpoint and IDOR lookup map, static/edge/header/CORS checks, bundle secret grep, CI smoke check) and the INCIDENT playbook (stop the writer, preserve, remove, check logs, rotate, notify, regression guard)."
---

# Data exposure: nothing sensitive is ever publicly reachable

A public bucket, a CDN, a static folder or an unauthenticated endpoint is a publishing system. Any
byte that lands there is public, forever, for anyone who guesses or lists the URL. This skill owns
the rules that keep private data out of public places, the audit that proves it, and the playbook
for the day it goes wrong.

The most common real incident is not an exploit. It is a well-meaning job (a backup, an export, a
log shipper) reusing the site's existing public storage client because it was already configured.

## 1. Rules (hold them in code, not in memory)

| Rule | What it means in practice |
|------|---------------------------|
| Public storage holds public content only | Product and marketing images, published documents, build assets. Never DB dumps, exports, CSVs, logs, secrets, config snapshots, shipping labels, invoices, customer documents or ID photos. |
| Private data lives in private storage | A separate private bucket, ideally in a separate cloud account with its own credentials. Backups get their own bucket in their own account (see `backup-resilience`). |
| One guarded choke point for public writes | Every write to public storage goes through one function (and a client-level middleware so a direct SDK call cannot skip it). It refuses denylisted keys, extensions and content types before any network call. |
| Fail closed | A new kind of data must be explicitly allowed. A blocked write throws and logs; it never falls back to "upload anyway". |
| Serve only what is meant to be served | Proxy routes that fetch from a bucket accept a bare file name only: reject `/`, `\`, `%`, `..`, NUL, leading dots and anything that is not its own basename, so an encoded slash (`%2F`) cannot reach another folder. |
| Private downloads use short-lived signed URLs | Minutes, not days. Issued only after an auth and ownership check. Never a permanent public URL for a private object. |
| No bypass hosts for private data | Provider dev URLs (for example `*.r2.dev`, raw `s3.amazonaws.com` website endpoints) stay disabled; the origin host should not serve what the WAF is meant to guard. |
| Nothing leaks from the build or the server | Source maps not published, `.env` and `.git` never in the web root, directory listing off, generic error bodies in production (log the detail server-side). |
| Uploads from users are private until approved | Avatars, review photos and attachments go to private storage; copy to public only after moderation; delete on rejection or account deletion. Strip EXIF. |
| Content type comes from the server | Derive it from the validated extension or sniffed bytes, never from the client's multipart MIME. Never serve user-influenced `text/html` or `image/svg+xml` from a same-site host. |

### The guard (shape, any stack)

```ts
// One policy constant, cited by tests. Checked inside the upload helper AND as client middleware.
const DENY_FOLDERS = /(^|\/)(backups?|exports?|dumps?|private|logs?)\//i;
const DENY_EXT = /\.(dump|pgdump|backup|sql|sql\.gz|bak|tar|tgz|gz|zip|7z|rar|csv|tsv|xlsx?|sqlite3?|db|env|pem|key|p12|pfx|log)$/i;
const DENY_TYPES = /^(application\/(sql|x-sql|gzip|zip|x-tar|vnd\.ms-excel|vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet|x-sqlite3)|text\/csv)/i;
export function assertPublicWriteAllowed(key: string, contentType?: string) {
  if (!key || key.includes("..") || key.includes("\0") || /(^|\/)\./.test(key)
      || DENY_FOLDERS.test(key) || DENY_EXT.test(key) || (contentType && DENY_TYPES.test(contentType))) {
    throw new PublicWriteBlockedError(key); // log it, alert on it
  }
}
```

Regression tests that must exist:
- the guard refuses a dump key, a `backups/` key, a CSV and a SQL content type, and allows one
  real example per legitimate call site;
- a raw SDK `PutObject` / multipart `Upload` / `CopyObject` on the public client is refused (the
  middleware, not just the helper);
- a static test that fails if any file other than the storage module builds a write command or a
  client against the public bucket, or if any file that runs `pg_dump` / `mysqldump` references
  the public bucket;
- `GET /<proxy-route>/a%2Fb.png` returns 404 without calling storage.

## 2. AUDIT: prove nothing sensitive is public

Read-only and low-volume: HEAD or a 1-byte range GET, never bulk downloads, never save customer
data. Report keys, sizes, types and field NAMES, never values.

1. **Inventory public storage.** List every public bucket (keys, sizes, content types, oldest and
   newest). Group by prefix and extension. Flag anything that is not public by design: dumps,
   archives, CSV/XLSX, JSON exports, logs, HTML/SVG, label or invoice PDFs, user uploads. Check
   bucket listing is off (`/`, `?list-type=2`) and provider dev URLs answer 401/404.
2. **Map every writer.** Grep for every put/upload/copy against public storage. For each call
   site record key prefix, data type and who can trigger it (admin, customer, anonymous). Any
   writer outside the guarded choke point is a finding.
3. **Map every proxy and static path.** Routes that read from storage or disk by name (`/uploads/:f`,
   `/img/:f`), the static root, SPA fallbacks. Probe with encoded separators (`%2F`, `%5C`,
   `..%2F`) on every host that serves them, including the origin host that skips the CDN/WAF.
4. **Map unauthenticated endpoints.** Every route reachable without a session: what fields does
   it return? Look for IDOR-style lookups (email plus ZIP, email plus order number, sequential
   ids, promo code to partner stats), `SELECT *` responses, enumeration oracles (different answer
   for known vs unknown email) and settings endpoints that publish server-side keys.
5. **Static, edge, header and CORS checks.** `/.env`, `/.git/HEAD`, `/package.json`, server
   source paths, `*.map` for the live bundle, directory listings, verbose error bodies on 500s,
   CORS reflecting arbitrary origins with credentials, missing `nosniff`/CSP on the CDN host, the
   origin reachable without the CDN.
6. **Bundle secret grep.** Pull the live JS bundle (and old build chunks kept in storage) and grep
   for key shapes (`sk_`, `AKIA`, `-----BEGIN`, `postgres://`, JWT-looking strings, any env var
   baked in at build time). Hand off secret scanning of the repo to Skill Starter Kit
   `security-gate` (gitleaks).
7. **CI smoke check.** A script that runs after every deploy and exits non-zero if any
   must-be-private URL answers 200/206 with real content: dump keys the old writer would have
   produced, `backups/` and similar folders, bucket listings, `.env`, `.git`, source maps,
   `%2F` proxy probes. A SPA fallback `200 text/html` for a non-HTML target counts as a miss, not
   an exposure; a WAF challenge is "inconclusive", not a pass.

Output a findings table (severity, where, what, evidence, fix) in `sec/threats/exposure-YYYY-MM-DD.md`.
Every confirmed finding goes to `exploit-verify` for a regression and `harden-stack` for the fix.

## 3. INCIDENT playbook (in this order)

1. **Stop the writer.** Kill switch or config change first (a disabled job, a revoked write
   credential), so no new copies appear while you clean up. Confirm the next scheduled run did
   not write.
2. **Preserve copies privately and verify them.** Download every exposed object to private
   storage the owner controls, check sizes and checksums (and for dumps, that they restore).
   They are now evidence and possibly the best backup you have.
3. **Remove the public copies and confirm 404.** Delete from the bucket, purge the CDN cache,
   then HEAD every exposed URL on every host (CDN, origin, provider dev URL, any proxy route
   with `%2F`) and confirm 404. Check replica disks or local caches that may hold copies.
4. **Check edge and access logs for any download.** CDN analytics and logs, origin access logs,
   every host that could serve the objects, for the whole window from first write to deletion.
   Note any gap in log coverage explicitly; an unverified window counts as "possibly accessed".
5. **Rotate every exposed secret if accessed (or if unverifiable).** DB passwords, API keys
   stored in settings tables, payment processor credentials, session secrets, webhook secrets.
   Force password resets if password hashes were exposed and access cannot be ruled out.
6. **Consider notification duties.** If personal data was or may have been accessed, the owner
   decides on customer, partner, payment processor or regulator notification. Give them the
   facts: what data, how many records, the window, the evidence.
7. **Add the regression guard.** The choke-point denylist, the static test, the CI smoke check,
   and an entry in `.agents/security-context.md` so the next agent knows the incident happened
   and what now prevents it.

## Works with →
- **attack-surface**: the exposure check is part of recon; this skill owns the storage and
  public-path side of it.
- **backup-resilience**: owns where backups go (private, encrypted, off-host). This skill blocks
  them from ever landing anywhere public.
- **exploit-verify** writes the regressions; **harden-stack** applies the fixes;
  **prod-debug** gathers log evidence during an incident.
- Skill Starter Kit **security-gate** (gitleaks for secrets in the repo and bundles).
- Upstream `hunting-broken-object-level-authorization`, `hunting-path-traversal-and-file-access`,
  `auditing-file-upload-and-content-handling`, `auditing-error-handling-and-information-exposure`,
  `finding-fail-open-flaws`.
