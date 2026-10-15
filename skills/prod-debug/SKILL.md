---
name: prod-debug
description: "Debug in production: incidents, crashes, memory leaks, race conditions that only reproduce under real traffic. Use for 'debug this production bug', 'investigate this crash', or any issue where the dev environment doesn't reproduce the problem. Complements systematic-debugging (code-level root cause) with runtime/observability depth. A leaked secret or exposed data is a data-exposure incident: that skill owns it, prod-debug only supplies log evidence."
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

## 4. Secrets / credential leaks and exposed data: hand off to `data-exposure`

A secret in a log, memory dump, error body or client bundle, or private data on a public URL, is
not debugged here. Load `data-exposure` and follow its INCIDENT playbook: it is the one owner
(rotate a leaked live credential first, then preserve, remove and confirm 404, check logs,
notify, regression guard). Do not run a separate rotate-and-stop sequence from this skill.

What prod-debug contributes when the playbook asks for it: the runtime evidence. Which log lines,
requests, builds or dumps contained the secret or served the data, the time window, and any gap
in log coverage. Never paste a secret value into notes or tickets.

## Works with →
- Superpowers **systematic-debugging** → hypothesis generation, bisection, root-cause.
- **fuzz-harness** → model the race/load conditions.
- **exploit-verify** → regression test.
- **harden-stack** → fix.
- **data-exposure** → owns leaked secrets and exposed data (its incident playbook); prod-debug
  supplies the log evidence.
- **backup-resilience** → an outage, ban or lost host is recovered from its restore guide.
- Skill Starter Kit **browser-verify** → screenshot/DevTools for frontend production bugs.