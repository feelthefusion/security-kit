---
name: attack-surface
description: "Reconnaissance: enumerate every entry point, source, sink, webhook, and dependency your site or app exposes. Use before any red-team pass or when asked 'what is our attack surface?' or 'map our routes for security.' Reads .agents/security-context.md and hands off to red-team. NOT for running the actual attack (see red-team) or confirming a lead (see adjudicating-taint-paths)."
---

# Attack-surface recon

Before you attack, you have to know what's there. This skill enumerates every externally reachable
path, source, sink, webhook, and dependency — producing a ranked lead list that `red-team` attacks.

## 1. Entry-point enumeration

From `.agents/security-context.md` and the repo itself:
- Every route (HTTP method + path) — parse the framework: Express `app.get/post/…`, Next.js
  `app/api/…`, Hono `app.get/post/…`, Fastify, etc.
- Every webhook/callback route — these are prime targets. Signature verification, idempotency,
  and replay go first (they are zero-touch: an attacker just POSTs).
- GraphQL endpoint (if present) — introspection, depth limits, batching attacks.
- WebSocket / SSE / real-time endpoints.
- File-upload endpoints (MIME validation server-side, storage outside web root?).
- AI/LLM endpoints (prompt injection surface).
- Password reset, MFA, and account-recovery flows.
- Any route that takes a user/object ID from the URL or body (IDOR candidates).
- Any route that redirects (open redirect candidates).

## 2. Source-to-sink mapping

For every entry point classified above:
- **Source** — what untrusted data enters (header, query, body, path, cookie, JWT).
- **Sink** — where does it end up (SQL, NoSQL, shell, eval, HTML template, file system, HTTP
  redirect, email body, SMS body, push payload, webhook dispatch)?
- **Sanitisers crossed** — what validation/encoding/casting happens in between? List each one.
  Mark assumptions (e.g. "the framework automatically HTML-escapes" — does it really, and does
  the stack's version have a known bypass?).

## 3. Dependency & secret posture

- Dependencies (package.json, requirements.txt, Gemfile, Cargo.toml) — version, age, known CVEs.
  Hand-off to the Skill Starter Kit's `security-gate` for `osv-scanner` + CVE database.
- Secrets in client bundles (Vite/Next.js/webpack `import.meta.env`, Expo `app.config.js`,
  public env vars) — any that would be leaked in a JS bundle or mobile binary.
- CI/CD secrets reachable from the repo (workflow_dispatch, PR workflows from forks, untrusted
  action pins) — hand-off to `zizmor` via security-gate.

## 4. Produce the lead list

Output a table, ranked by risk (blast radius × ease of exploitation):

| # | Route / source | Sink(s) | Red flag | Priority |
|---|---------------|---------|----------|----------|
| 1 | POST /api/webhooks/resend | DB insert (order event) | signature not verified first? | critical |
| 2 | GET /api/users?token= | DB lookup | token in query param (logged in CDN/nginx) | high |
| … | … | … | … | … |

Every row becomes a `red-team` target. The `red-team` attack-vector graphs live in
`sec/attacks/<id>/`, keyed from this table's row number.

Record findings in `sec/threats/recon-YYYY-MM-DD.md`.

## Works with →
- **red-team** → attacks each lead with the adversarial protocol.
- **exploit-verify** → proves findings.
- **harden-stack** → fixes them.
- Upstream `mapping-attack-surface`, `hunting-broken-object-level-authorization`, `auditing-webhook-authenticity-and-callback-trust`.