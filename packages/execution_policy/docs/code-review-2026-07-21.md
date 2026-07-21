# execution_policy — pre-adoption code review (2026-07-21)

Review of `execution_policy` 0.2.0 before adopting it as the resilience layer of
a production Flutter SDK (wrapping `dio` calls: one-off decision requests with
retry-until-cancelled semantics, and batch event flushes with backoff + circuit
breaker). Every finding was verified against the source. Line references are to
the 0.2.0 sources as reviewed; all findings below are **resolved in 0.3.0**.

## Verdict

**Patch before adoption.** Shipped as **0.3.0** with the fixes and prod-readiness
work below; see `CHANGELOG.md`.

## (a) Bugs

| ID | Severity | Area | Defect | Resolution (0.3.0) |
|----|----------|------|--------|--------------------|
| B1 | **Critical** | `retry_policy.dart` `delayFor` | `(baseMs * pow(2, attempt-1)).toInt()` is int64 math; at attempt ~57 (baseDelay 200ms) it wraps **negative**, and the `min(ms, maxDelay)` clamp then picks the negative value → `Future.delayed` treats it as zero → a full-speed retry hot loop. `maxDelay` never protected. | Curve computed and capped in `double` space **before** jitter; non-finite guarded; result clamped to `[0, maxDelay]`. Regression test at attempts 56–1000. |
| B2 | Major | `circuit_breaker_policy.dart` | Open circuit threw a bare `StateError('Circuit is open')`; callers had to string-match, and it collided with retry's own internal `StateError`. | Typed `CircuitOpenException(retryAfter)`. |
| B3 | Major | `circuit_breaker_policy.dart` | Half-open admitted **every** concurrent call, not one — thundering herd on a recovering backend. | Single in-flight probe gate; concurrent callers get `CircuitOpenException(Duration.zero)`. Concurrency test added. |
| B4 | Major | `fallback_policy.dart` | `catch (_)` swallowed **everything**, including `Error`s (a deserialization `TypeError` became an invisible "success"). | `on Exception catch` (Errors propagate) + optional `shouldHandle`; fallback receives the error. |
| B5 | Major | `retry_policy.dart` | `onError` was fire-and-forget (unhandled async rejection; a **synchronous** throw replaced the real error and aborted remaining retries). `retryIf` throws were unguarded too. | `onError` awaited inside its own try/catch; `retryIf`/`shouldContinue` guarded (throw ⇒ treated as "do not retry"). Tests added. |
| B6 | Minor | `retry_policy.dart` | `maxAttempts` guarded only by `assert` (stripped in release) → `maxAttempts: 0` yielded a misleading `StateError`. | Runtime `ArgumentError` in the `RetryPolicy` constructor. |
| B7 | Minor | `retry_policy.dart` | Jitter applied **before** the cap (vanishes at the tail where herd desync matters most); `Random()` re-instantiated per call. | Jitter applied after the clamp; shared `static final Random`. |
| B8 | Minor | `policy_builder.dart` | `List.sort` is unstable; two policies of the same type (e.g. two `.retry`) had arbitrary relative order and silently nested. | Duplicate policy type ⇒ `StateError`. |
| B9 | Minor | `timeout_policy.dart` | `execute` was not `async`; a synchronous throw from `action()` escaped synchronously. | `execute` is `async`. |

### Verified non-bugs (0.2.0, retained)
- `maxAttempts` is total attempts (loop `1..maxAttempts`); `delayFor(attempt)`
  first backoff = `baseDelay`; no delay after the final failure; `Future.timeout`
  cancels its timer on early completion and discards late errors; `TimeoutException`
  propagates into retry and is retried by default; half-open success resets and
  closes, half-open failure re-opens.

## (b) Design gaps addressed

- **G1 Cancellation** — 0.2.0 had none: the retry-until-widget-dies flow was not
  expressible and a backoff `Future.delayed` could not be interrupted. Added
  `CancellationToken` (checked before each attempt/backoff, and raced against the
  sleep) plus a cheap `shouldContinue` gate.
- **G4 Observability** — added `onRetry(error, attempt, delay)`, breaker
  `onStateChange(from, to)`, and read-only `state` / `failureCount` getters.

## (c) Documented semantics (not bugs)

- **Chain order is fixed** (`Fallback → CircuitBreaker → Retry → Timeout`)
  regardless of call order: timeout is **per-attempt**, breaker is **outside**
  retry (one `execute` can record up to `maxAttempts` breaker failures — size
  `failureThreshold` accordingly). Now documented on `PolicyBuilder`.
- **Breaker state is per-instance**; a builder rebuilt per call never trips — hold
  ONE builder per endpoint. `copy()` shares the stateful breaker instance (covered
  by a test).

## Test coverage delta

29 → 45 tests. New: backoff overflow (B1), throwing `retryIf`/`onError` (B5),
`shouldContinue` + `CancellationToken` up-front and mid-backoff (G1), `onRetry`
(G4), fallback Error-passthrough + `shouldHandle` (B4), synchronous-throw timeout
(B9), typed `CircuitOpenException` + single-probe half-open (B2/B3), duplicate-type
guard (B8), and `copy()` breaker sharing.
