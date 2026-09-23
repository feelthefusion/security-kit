---
name: harden-stack
description: "Defense-in-depth fixes for vulnerabilities found by red-team/attack-surface. Use when fixing a confirmed vulnerability, hardening auth/session/webhooks/CORS, or asked to make code production-safe. Never placeholders, never commented TODO — parameterized queries, strict typing, error insulation, logging hooks."
---

# Harden the stack — defense-in-depth fixes

The fix, not the band-aid. Every fix is structural and production-ready: parameterised queries,
strict typing, error insulation (no raw stack trace to the user), and logging hooks. The
`exploit-verify` regression gates the fix — red before, green after.

## Fix maps (by vulnerability class)

### SQL / NoSQL injection
- Parameterised queries / prepared statements / ORM bind params — never string concatenation.
- For dynamic identifiers (table/column names that legitimately can't be bound): validate against
  a server-side allow-list, never skip to string interpolation.

### IDOR / broken object-level authorization
- Ownership check on read AND write, at the data layer (not only in the UI).
- Prefer scoping queries to the authenticated principal (WHERE owner = $current_user) over
  fetch-then-compare.

### Command / eval injection
- No user input flows to `exec`, `spawn`, `eval`, `Function`, `child_process`, `os.system`.
- If a subprocess is truly required: fixed arg arrays (`spawn` with `{ shell: false }`, no string
  command line), never tainted strings.

### Webhooks (Resend / Telnyx / any callback)
- Verify the cryptographic signature BEFORE the payload touches any handler; constant-time compare.
- Timestamp-bound idempotency (store + check nonce/event-id, atomic insert with unique constraint,
  reject replays outside a time window).
- Reject non-UTF8, oversized, or malformed payloads before parsing.

### Auth / session
- bcrypt/argon2 for passwords; scrypt/argon2 for tokens; never MD5/SHA1 for secrets.
- Session rotation on privilege change; httpOnly + Secure + SameSite cookies; short JWT exp with
  `aud`/`iss` validation and an algorithm allow-list.
- Null-byte / empty-header / type-juggling: strict === comparisons, `typeof` guards, explicit
  string coercion before compare.

### Headers / CORS / CSRF
- CORS: explicit origin list, never `*` with credentials; reflect only the expected origin.
- CSRF: SameSite=Lax/Strict + an anti-CSRF token on state-changing routes.
- CSP, X-Content-Type-Options: nosniff, X-Frame-Options/frame-ancestors, HSTS.
- `X-Robots-Tag` if you want the page out of search (see `stealth-mode`).

### Race conditions / concurrency
- `SELECT … FOR UPDATE`, atomic `UPDATE … WHERE` guards, or a concurrency queue for read-modify-write
  on balances, credits, counters, and inventory.
- Idempotency keys on payments and webhook-triggered writes.

### Fail-open flaws
- Auth middleware returns `403` on error, not `next()`; allow-lists are closed by default.

## Output requirements (per red-team's output restraints)
- Defensive try-catch that maps known errors to safe responses and re-raises unknown ones.
- Strict typing (TypeScript / type hints / zod / pydantic at the boundary).
- Error insulation: log the full stack server-side; return a generic message + correlation ID to
  the caller.
- Logging hooks: auth attempt, webhook arrival, payment state change, secret access — keyed by
  the same correlation ID.

## Verification
The `exploit-verify` regression must flip from RED to GREEN with this fix. Paste the green run.

## Works with →
- **exploit-verify** → the regression proving the fix.
- **red-team** → re-run the attack-vector graph to confirm the class (not just the instance) is gone.
- Skill Starter Kit **security-gate** (`gitleaks` for secrets, `osv-scanner` for CVE, `zizmor` for CI) + **guardrails** (block destructive commands).
- Upstream `finding-fail-open-flaws`, `auditing-guard-gaps`, `finding-crypto-misuse`.