---
name: prod-debug
description: "Debug in production — incidents, crashes, memory leaks, race conditions that only reproduce under real traffic. Use for 'debug this production bug', 'investigate this crash', 'trace this leaked secret', or any issue where the dev environment doesn't reproduce the problem. Complements systematic-debugging (code-level root cause) with runtime/observability depth."
---

# Production debugging — runtime is the truth

Bugs that only fire in production: race conditions between real users, memory leaks after days of
traffic, crash patterns that don't appear in dev. `systematic-debugging` (Superpowers) is for
understanding the root cause in code; this skill is for getting the evidence FROM production.

## 1. Evidence-first — never guess

Before any theory, lock in the facts:
- **Logs** — correlation ID (see `harden-stack` — every handler should log one). Find the exact
  request chain: webhook → handler → DB → response. Is there a gap? A crash at a specific step?
- **Traces** — if the stack has OpenTelemetry/tracing, follow the span. Latency spike, missing
  span, error recorded but not propagated.
- **Crash / core dump** — stack trace, signal, memory state. Node: `--abort-on-uncaught-exception`
  + `llnode` / `node-report`. Python: `faulthandler`. Go: `GOTRACEBACK=crash`.
- **Memory** — heap snapshots (Node: `--heapsnapshot-signal=SIGUSR2`; Python: `tracemalloc`).
  Is it a leak (growing heap) or just a spike under load?
- **DB** — query at the time of the incident: locks held, long-running transactions, row counts,
  slow queries (`pg_stat_activity`). Radio "SELECT … FOR UPDATE" on a hot row.
- **APM / metrics** — request rate, error rate, p50/p99 latency, memory/CPU at the incident time.

## 2. Reproduce (or narrow)

- **Replay the exact request** — copy the raw webhook/HTTP payload, replay to a staging endpoint.
  Does it reproduce? If yes: the bug is in request processing. If no: it's state or concurrency.
- **Concurrency** — was it the Nth concurrent request? The Nth after a specific sequence?
  `fuzz-harness` can model this.
- **State** — extract the DB/Redis row state from before the incident (if you have point-in-time
  recovery or a replica lag). Replay against that state.

## 3. Fix (in prod-safe order)

1. **Stop the bleed** — feature flag it off, circuit-break, or rate-limit the affected route.
   Then investigate under no pressure.
2. **Understand** — hand-off to `systematic-debugging` (Superpowers) with the evidence gathered.
3. **Test** — `exploit-verify` → write a regression that reproduces the conditions (or the closest
   approximation). `fuzz-harness` to stress the fix.
4. **Ship** — enable the fix, monitor the metric; confirm the crash/leak rate drops.

## 4. Secrets / credential leaks (production)

If a secret leaked in a log/memory dump/client bundle:
1. Rotate it immediately (the kit can't rotate it for you — use AWS Secrets Manager / Railway
   env / 1Password CLI — but the skill tells you to do it first).
2. Find where it leaked: grep logs, scan client bundles (`sec-settings stealth on` header doesn't
   help here — this is about accidental exposure).
3. `harden-stack` to prevent recurrence (error insulation, no secrets in env vars pushed to
   logs, no `console.log(process.env)` equivalents).

## Works with →
- Superpowers **systematic-debugging** → hypothesis generation, bisection, root-cause.
- **fuzz-harness** → model the race/load conditions.
- **exploit-verify** → regression test.
- **harden-stack** → fix.
- Skill Starter Kit **browser-verify** → screenshot/DevTools for frontend production bugs.