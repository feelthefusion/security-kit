---
name: fuzz-harness
description: "Fuzzing, property-based, load and race testing — find the bugs that only fire under malformed input or pressure. Use when asked to fuzz an endpoint/parser, property-test a function, load-test, or hunt race conditions empirically. Complements red-team (logic) with dynamic/empirical testing."
---

# Fuzz harness — dynamic & stress testing

`red-team` finds flaws by reading code. This skill finds them by *executing*: fuzzing parsers and
endpoints, property-testing invariants, load-testing for races and resource exhaustion. Use it
when you need empirical proof, not just a code read.

## 1. Pick the right tool for the job

| Goal | Tool | Notes |
|------|------|-------|
| Parser/decoder bugs (JSON, URL, headers, body) | property-based: `fast-check` (TS), `hypothesis` (py), `prop.test`/quickcheck | invariant-driven, shrinks counter-examples |
| HTTP endpoint robustness | fuzz the route with malformed bodies/params via curl/httpx/`ffuf`-style mutation | watch for 500s, stack-traces, hang-ups |
| Business-rule invariants | property tests on pure functions (price calc, credits, coupons, rate limits) | `sum(order) >= 0`, `credits never < 0`, `coupon applied once` |
| Race conditions | run N concurrent requests against the endpoint with a shared counter/balance | measure: lost updates, double-redemption |
| Resource exhaustion | large payloads, many connections, slow-loris, zip bombs | timeouts, body-size caps, connection limits |
| DB integrity under concurrency | concurrent inserts/updates against a unique key | assert no duplicate idempotency keys |

## 2. Property-based testing pattern

Write an invariant, let the library generate inputs, let it shrink the failing case:
```ts
// fast-check: price/credits invariant
import fc from 'fast-check';
fc.assert(fc.property(fc.float({min: 0}), fc.integer({min: 1}), (price, qty) => {
  const total = price * qty;
  return total >= 0;            // your business invariant
}));
```

## 3. Race-condition test (empirical)

```ts
// fire N parallel "redeem credits" requests, assert only one succeeds / balance never < 0
const results = await Promise.all(Array.from({length: 20}, () => redeem(code, userId)));
const successes = results.filter(r => r.ok).length;
expect(successes).toBe(1);       // idempotency/unique constraint held
// AND the DB balance matches (SELECT after the dust settles)
```

## 4. Load / resource test

- Hammer an auth or webhook route; assert it rate-limits (429) rather than crashing.
- Send a huge body; assert a 413/400 and no OOM.
- Confirm timeouts exist and no slow-loris.

## 5. Hand-off anything found

A crash, hang, duplicate, or invariant violation is a *finding*. Hand it to:
- `red-team` (understand the class) → `exploit-verify` (minimal PoC + regression) → `harden-stack` (fix).

Record the fuzz/load run and its corpus in `sec/attacks/fuzz-YYYY-MM-DD.md`.

## Works with →
- **red-team** → turns a fuzz finding into an attack-vector graph.
- **exploit-verify** → regression test.
- **harden-stack** → the fix (rate limits, size caps, locks, idempotency).
- **prod-debug** → if it only reproduces in prod.
- Upstream `reviewing-rate-limiting-and-abuse-controls`.