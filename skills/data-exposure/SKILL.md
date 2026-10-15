---
name: data-exposure
description: "Use when anything could make private data or a secret publicly reachable: public bucket, CDN, static folder, uploads route, backup in public, database dump or export in a bucket, PII leak, leaked secret or API key (in the JS bundle, a log, an error body or a crash dump), signed URL, source maps, .env/.git exposure, directory listing, verbose errors, HTML/SVG on a same-site CDN, %2F proxy paths, origin reachable without the WAF, or a data exposure audit. Owns the rule 'nothing sensitive is ever publicly reachable': the allowlist write guard, the AUDIT procedure (public bucket inventory, unauthenticated endpoint and IDOR lookup map, same-site active content, encoded path probes, origin bypass, static/header/CORS checks, bundle secret grep, CI smoke check) and the INCIDENT playbook for exposed data and leaked secrets (stop the writer or rotate, preserve, remove, check logs, notify, regression guard)."
---

# Data exposure: nothing sensitive is ever publicly reachable

A public bucket, a CDN, a static folder or an unauthenticated endpoint is a publishing system. Any
byte that lands there is public, forever, for anyone who guesses or lists the URL. This skill owns
the rules that keep private data and secrets out of public places, the audit that proves it, and
the playbook for the day it goes wrong.

The most common real incident is not an exploit. It is a well-meaning job (a backup, an export, a
log shipper) reusing the site's existing public storage client because it was already configured.

## 1. Rules (hold them in code, not in memory)

| Rule | What it means in practice |
|------|---------------------------|
| Public storage holds public content only | Product and marketing images, published documents, build assets. Never DB dumps, exports, CSVs, JSON snapshots, logs, secrets, config snapshots, shipping labels, invoices, customer documents or ID photos. |
| Private data lives in private storage | A separate private bucket, ideally in a separate cloud account with its own credentials. Backups get their own bucket in their own account (see `backup-resilience`). |
| One guarded choke point for public writes | Every write to public storage goes through one function (and a client-level middleware so a direct SDK call cannot skip it). It is an **allowlist**: the write must match an allowed key prefix AND an allowed extension for that prefix AND an allowed content type for that extension. Everything else is refused before any network call. |
| Fail closed | A new kind of data is refused until someone adds an explicit allow rule for it, with a test. A blocked write throws and logs; it never falls back to "upload anyway". The denylist is only a second belt that also runs; it is never the reason a write is allowed. |
| Serve only what is meant to be served | Proxy routes that fetch from a bucket accept a bare file name only: reject `/`, `\`, `%`, `..`, NUL, leading dots and anything that is not its own basename, checked after URL decoding, so an encoded slash (`%2F`, `%252F`) cannot reach another folder. Prefix the key server-side (`products/` + name); never let the path pick the prefix. |
| Private downloads use short-lived signed URLs | Minutes, not days. Issued only after an auth and ownership check. Never a permanent public URL for a private object. |
| No bypass hosts | Provider dev URLs (for example `*.r2.dev`, raw `s3.amazonaws.com` website endpoints) and provider default app domains stay disabled or locked. The origin only accepts traffic from the CDN/WAF (authenticated origin pulls, a secret header checked at the origin, or an IP allowlist), so nothing the WAF guards is reachable directly. |
| Nothing leaks from the build or the server | Source maps not published, `.env` and `.git` never in the web root, directory listing off, generic error bodies in production (log the detail server-side), no secrets in client env vars or logs. |
| Uploads from users are private until approved | Avatars, review photos and attachments go to private storage; copy to public only after moderation; delete on rejection or account deletion. Strip EXIF. |
| No active content on a same-site host | Content type comes from the server (the validated extension), never from the client's multipart MIME. `text/html`, `image/svg+xml`, XML and XHTML are not on the public allowlist. If such files must be served from a host under the site's own domain, serve them with `Content-Disposition: attachment` (force download) or `Content-Security-Policy: sandbox`, plus `X-Content-Type-Options: nosniff`, or move them to a separate registrable domain. |

### The guard (shape, any stack)

```ts
// One policy constant, cited by tests. Checked inside the upload helper AND as client middleware.
// ALLOWLIST: prefix x extension x content type. Anything not listed is refused (fail closed).
const PUBLIC_WRITE_ALLOW: Record<string, Record<string, string>> = {
  "products/":  { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", avif: "image/avif" },
  "marketing/": { jpg: "image/jpeg", png: "image/png", webp: "image/webp", mp4: "video/mp4" },
  "docs/":      { pdf: "application/pdf" },
  // add a rule (and a test) for each new legitimate call site; never add html, svg, xml, json, csv, archives
};
// Second belt only. It can refuse an allowed-looking write; it can never allow one.
const DENY = /(^|\/)(backups?|exports?|dumps?|snapshots?|db|private|logs?|tmp)\/|\.(sql|dump|pgdump|bak|gz|tgz|zst|xz|bz2|zip|7z|tar|csv|tsv|xlsx?|json|ndjson|parquet|sqlite3?|db|env|pem|key|p12|pfx|enc|gpg|age|log|txt)(\.|$)/i;
const SAFE_KEY = /^[A-Za-z0-9][A-Za-z0-9_\-/]*\.[A-Za-z0-9]+$/;   // no %, \, spaces, NUL, leading dots

export function publicWrite(key: string, requestedType?: string) {
  const prefix = Object.keys(PUBLIC_WRITE_ALLOW).find((p) => key.startsWith(p));
  const ext = key.slice(key.lastIndexOf(".") + 1).toLowerCase();
  const type = prefix ? PUBLIC_WRITE_ALLOW[prefix][ext] : undefined;   // the server picks the type
  const ok = SAFE_KEY.test(key) && !key.includes("..") && !key.includes("//") && !/(^|\/)\./.test(key)
    && type !== undefined && (requestedType === undefined || requestedType.split(";")[0].trim().toLowerCase() === type)
    && !DENY.test(key);
  if (!ok) throw new PublicWriteBlockedError(key, requestedType); // log it, alert on it
  return { key, contentType: type };   // the upload uses THIS type, never the caller's
}
```

Regression tests that must exist:
- the guard refuses a key under an unlisted prefix (`snapshots/customers.json`, `db/site.dump.zst`),
  an unlisted extension under an allowed prefix (`products/list.json`, `products/a.svg`,
  `products/a.html`), an allowed extension with a mismatched type (`products/a.png` with
  `application/octet-stream`), a denylisted folder under an allowed prefix
  (`products/backups/a.png`) and an encoded or dotted key (`products/a%2Fb.png`,
  `products/.env.png`), and allows one real example per legitimate call site;
- a raw SDK `PutObject` / multipart `Upload` / `CopyObject` on the public client is refused (the
  middleware, not just the helper);
- a static test that fails if any file other than the storage module builds a write command or a
  client against the public bucket, or if any file that runs `pg_dump` / `mysqldump` references
  the public bucket;
- `GET /<proxy-route>/a%2Fb.png` and `/<proxy-route>/a%252Fb.png` return 404 without calling
  storage.

## 2. AUDIT: prove nothing sensitive is public

Read-only and low-volume: HEAD or a 1-byte range GET, never bulk downloads, never save customer
data. Report keys, sizes, types and field NAMES, never values.

Start from `attack-surface`'s route list (`sec/threats/recon-*.md`). This audit does not re-map
routes; if there is no current recon, run `attack-surface` first and come back.

1. **Inventory public storage.** List every public bucket (keys, sizes, content types, oldest and
   newest). Group by prefix and extension. Flag anything that does not match the allowlist:
   dumps, archives, CSV/XLSX, JSON exports, logs, HTML/SVG, label or invoice PDFs, user uploads.
   Check bucket listing is off (`/`, `?list-type=2`) and provider dev URLs answer 401/404.
2. **Map every writer.** Grep for every put/upload/copy against public storage. For each call
   site record key prefix, data type and who can trigger it (admin, customer, anonymous). Any
   writer outside the guarded choke point, or any write the allowlist would refuse, is a finding.
3. **Same-site active content.** Any object or route that serves `text/html`, `image/svg+xml`,
   XML or XHTML (or sniffs into them) from a host under the site's own domain (for example a
   `cdn.` or `files.` subdomain) is stored XSS with the site's cookies in scope. Check the
   response headers: it must force download (`Content-Disposition: attachment`) or carry
   `Content-Security-Policy: sandbox`, with `nosniff`; otherwise move it to a separate domain.
4. **Path-encoded folder access through app proxies.** For every route in the recon list that
   reads from storage or disk by name (`/uploads/:f`, `/img/:f`, SPA fallbacks, image resizers),
   request `a%2Fb`, `..%2F`, `%252F`, `%5C` and a private prefix (`backups%2F<name>`). A proxy
   that decodes `%2F` and builds the key from it reaches every folder in the bucket, including
   private prefixes when its credential can read them. Probe every host that serves the route.
5. **Origin bypass.** Find every host that reaches the origin without the CDN/WAF: the provider
   default app domain, the origin IP, a raw bucket endpoint, old DNS names. Request the paths the
   WAF blocks or challenges, the private prefixes and the probes from steps 3 and 4 directly on
   each one. Anything the origin serves that the WAF would have stopped is a finding; the fix is
   to lock the origin to the CDN (see the rule above).
6. **Unauthenticated responses.** For every route in the recon list reachable without a session:
   what fields does it return? Look for IDOR-style lookups (email plus ZIP, email plus order
   number, sequential ids, promo code to partner stats), `SELECT *` responses, enumeration oracles
   (different answer for known vs unknown email) and settings endpoints that publish server-side
   keys.
7. **Static, header and CORS checks.** `/.env`, `/.git/HEAD`, `/package.json`, server source
   paths, `*.map` for the live bundle, directory listings, verbose error bodies on 500s, CORS
   reflecting arbitrary origins with credentials, missing `nosniff`/CSP on the CDN host.
8. **Bundle secret grep.** This skill owns secrets in client bundles (attack-surface hands them
   here). Pull the live JS bundle, mobile bundle config and old build chunks kept in storage, and
   grep for key shapes (`sk_`, `AKIA`, `-----BEGIN`, `postgres://`, JWT-looking strings, any
   server env var baked in at build time through `NEXT_PUBLIC_`, `VITE_`, `EXPO_PUBLIC_` and the
   like). Repo secret scanning stays with Skill Starter Kit `security-gate` (gitleaks).
9. **CI smoke check.** A script that runs after every deploy and exits non-zero if any
   must-be-private URL answers 200/206 with real content, on the CDN host AND every origin host
   from step 5: dump keys the old writer would have produced, `backups/` and similar folders,
   bucket listings, `.env`, `.git`, source maps, `%2F` and `%252F` proxy probes, and any HTML/SVG
   on a same-site host without the download or sandbox headers. A SPA fallback `200 text/html`
   for a non-HTML target counts as a miss, not an exposure; a WAF challenge is "inconclusive",
   not a pass.

Output a findings table (severity, where, what, evidence, fix) in `sec/threats/exposure-YYYY-MM-DD.md`.
Every confirmed finding goes to `exploit-verify` for a regression and `harden-stack` for the fix.

## 3. INCIDENT playbook (in this order)

This is the one playbook for exposed data AND leaked secrets (a key in the bundle, a log, an error
body, a crash dump). `prod-debug` hands every such case here and supplies runtime evidence on
request.

1. **Stop the writer, or rotate the leaked secret.** For exposed data: kill switch or config
   change first (a disabled job, a revoked write credential), so no new copies appear while you
   clean up; confirm the next scheduled run did not write. For a leaked live credential: rotate
   or revoke it now, before anything else, without waiting for proof of access, then find and
   stop what leaked it (the build var, the log line, the error handler).
2. **Preserve copies privately and verify them.** Download every exposed object to private
   storage the owner controls, check sizes and checksums (and for dumps, that they restore).
   They are now evidence and possibly the best backup you have. For a secret, record where it
   appeared and since when (build ids, log ranges); never paste the secret value.
3. **Remove the public copies and confirm 404.** Delete from the bucket, purge the CDN cache,
   rebuild the bundle without the secret, then HEAD every exposed URL on every host (CDN,
   origin, provider dev URL, any proxy route with `%2F`) and confirm 404. Check replica disks,
   old build chunks and local caches that may hold copies.
4. **Check edge and access logs for any download.** CDN analytics and logs, origin access logs,
   every host that could serve the objects, for the whole window from first write to deletion
   (`prod-debug` pulls the log evidence). Note any gap in log coverage explicitly; an unverified
   window counts as "possibly accessed".
5. **Rotate every secret the exposed data contained, if accessed (or if unverifiable).** DB
   passwords, API keys stored in settings tables, payment processor credentials, session
   secrets, webhook secrets. Force password resets if password hashes were exposed and access
   cannot be ruled out. (A leaked live credential was already rotated in step 1.)
6. **Consider notification duties.** If personal data was or may have been accessed, the owner
   decides on customer, partner, payment processor or regulator notification. Give them the
   facts: what data, how many records, the window, the evidence.
7. **Add the regression guard.** The allowlist rule or test that would have refused it, the
   static test, the CI smoke check, and an entry in `.agents/security-context.md` so the next
   agent knows the incident happened and what now prevents it.

## Works with →
- **attack-surface**: owns route mapping; it hands the route list, public-storage checks and
  bundle secrets to this skill, which does not re-map routes.
- **prod-debug**: routes every secret or credential leak and exposure incident here; gathers the
  runtime and log evidence for steps 2 and 4.
- **backup-resilience**: owns where backups go (private, encrypted, off-host). This skill blocks
  them from ever landing anywhere public.
- **exploit-verify** writes the regressions; **harden-stack** applies the fixes (origin lock,
  headers, proxy validation).
- Skill Starter Kit **security-gate** (gitleaks for secrets in the repo).
- Upstream `hunting-broken-object-level-authorization`, `hunting-path-traversal-and-file-access`,
  `auditing-file-upload-and-content-handling`, `auditing-error-handling-and-information-exposure`,
  `finding-fail-open-flaws`.
