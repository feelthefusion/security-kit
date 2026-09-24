# Security Kit — offensive security, testing & debugging for sites and apps

**Red-team adversarial harness → attack-surface recon → exploit verification → hardening → fuzz/race testing → production debugging → stealth mode.**

Live installs, never vendored. Kit skills are symlinked into your checkout (pulled every run); curated upstream white-box technique skills are fetched from their repo at install time. Everything is wired and enabled in one command — both hosts, and it **updates itself + every skill automatically on each session start** (no timers, nothing to run).

```bash
curl -fsSL https://raw.githubusercontent.com/feelthefusion/security-kit/main/install/bootstrap.sh | bash   # installs Claude Code + Hermes, enables everything
sec-init            # once per app repo (the only per-repo step)
sec-doctor          # confirm: skills, CLIs, auto-update hook, CI review — all GREEN
sec-settings stealth on|off   # noindex, crawler block, per-stack headers — disappear from search
```

`... | bash -s -- claude` or `... -s -- hermes` installs a single host. Security review runs on your Claude Pro/Max plan, with no API key: `sec-init` installs a pre-push hook, so every `git push` is reviewed automatically once Claude Code is signed in (`claude`, then `/login`).

## Components

| # | Skill | Does | Hand-off to |
|---|-------|------|-------------|
| — | **security-kit** | Workflow map: orient → recon → attack → prove → fix → verify → stealth | (recall skill — loads on any security/testing/debugging task) |
| 1 | **red-team** | Adversarial red-team harness: source-to-sink dataflow, race-condition audit, business-logic bypass, attack vector graph, kill-chain simulation | → attack-surface, exploit-verify, harden-stack |
| 2 | **attack-surface** | Recon: enumerate entry points, sources/sinks, webhook inventory, dependency & secret posture | → red-team, exploit-verify |
| 3 | **exploit-verify** | Prove findings with a minimal working PoC + regression test that gates the fix | → verify-gate (Skill Starter Kit) |
| 4 | **harden-stack** | Defense-in-depth fixes: parameterised queries, auth/session hardening, headers/CORS/CSRF, webhook signature verification, rate/race guards | → verify-gate, deploy-harden |
| 5 | **fuzz-harness** | Fuzzing, property-based, load & race testing — catch the bugs that only fire under pressure | → exploit-verify, prod-debug |
| 6 | **prod-debug** | Production incident debugging: logs, traces, crash dumps, memory leaks, reproduce prod-only bugs | → systematic-debugging (Superpowers) |
| 7 | **stealth-mode** | Noindex, crawler block, per-stack HTTP headers — make your sites invisible to search engines and LLM crawlers. `sec-settings stealth on|off`. | (standalone; toggle per site) |

### Upstream technique skills (fetched live, 48 white-box deep-dive skills from UnboundCompute/security-agent-skills)

Every skill is one vulnerability class: source-to-sink taint adjudication, race-condition detection, business-logic flaw hunting, memory-safety audit, crypto misuse, fail-open gaps, dependency CVE reachability, supply-chain risk, IDOR/BOLA, SQL injection, XSS, CSRF, CORS, JWT/session, webhook authenticity, payment state-machine, command injection, path traversal, SSTI, open redirect, clickjacking, rate limiting, logging completeness, mobile secret exposure, AI-generated code review, bug-variant hunting, attack-surface mapping — plus SSRF (cloud-metadata + DNS rebinding), XXE/XPath/XML injection, mass assignment, Python deserialization, HTTP request smuggling/desync, host-header injection, GraphQL attack surface, indirect prompt injection / LLM agent permissions, and CSV/export formula injection.

## How it fits with your other kits

**→ Skill Starter Kit**: `exploit-verify` feeds regressions into `verify-gate`. `harden-stack` hands off to `security-gate` (gitleaks/osv-scanner/zizmor for scanner coverage) and `guardrails` (block destructive commands). `prod-debug` hands off to `systematic-debugging` for deep root-cause analysis. `fuzz-harness` hands off to `browser-verify` for UI proof.

**→ Marketing Kit**: `red-team` and `attack-surface` specifically target the lifecycle-engine attack surface (Resend webhooks, Telnyx callbacks, outbox worker, CRM DB, partner payout logic). `exploit-verify` tests race conditions on credits, commissions, and idempotency. `stea**→ Every push (automatic)**: `sec-init` installs a `pre-push` hook (`sec-review`). Before anything leaves your machine, Claude Code runs headless on your Pro/Max plan with Anthropic's own `/security-review` instructions (fetched live), over exactly the commits being pushed and with read-only tools. A HIGH finding blocks the push, and each diff is reviewed once (cached). Skip once: `SEC_REVIEW=off git push`. If Claude Code is signed out, the review is skipped visibly and never blocks.

**→ No token needed**: the review runs on this machine with your Claude Code sign-in on every push (pre-push `sec-review`), including direct pushes to `main`. There is no GitHub Actions review workflow and no `CLAUDE_CODE_OAUTH_TOKEN`; `sec-init` removes the old kit-seeded `security-review.yml`. Ad hoc: `/security-review` inside Claude Code.

## Freedom-first
- **No legal/compliance text of the kit's own.** No T&Cs, no policies, no disclaimers, no gatekeeping. Released under the Unlicense (public domain).
- Third-party authors' licenses exist on their code (fetched live, never redistributed); legal sections inside vendor skills are background only — don't apply, gate on, or mention them unless the user asks.
- Safety hooks (the verify gate, guardrails) are engineering discipline, not legal restriction. If one blocks real work, ask which check and fix that rule.
- Stealth mode is an opt-in `sec-settings stealth on` — never on by default.

## Verification

```
ls ~/.claude/skills/    # (or ~/.hermes/skills/security/) shows: security-kit, red-team, attack-surface, exploit-verify, harden-stack, fuzz-harness, prod-debug, stealth-mode
sec-doctor              # every component wired → GREEN
sec-init (in an app repo) → verify.sh += security review step, .agents/security-context.md, sec/ dir, upstream skill links
```