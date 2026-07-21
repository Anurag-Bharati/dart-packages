# Changelog

## [0.3.0] - 2026-07-21
### Fixed
- **Backoff overflow (critical):** the exponential curve is now computed and
  capped in `double` space before jitter, so a large attempt count can no longer
  overflow `int64` into a negative/zero delay that bypassed `maxDelay`.
- **Circuit breaker:** rejects with a typed `CircuitOpenException` (carrying
  `retryAfter`) instead of a bare `StateError`; half-open now admits exactly one
  probe (concurrent callers are rejected, preventing a thundering herd).
- **Fallback:** catches only `Exception`s — `Error` subtypes (`TypeError`,
  `StateError`, …) propagate so real bugs stay visible. Added an optional
  `shouldHandle` predicate, and the fallback now receives the triggering error.
- **Retry hooks:** `onError` is awaited defensively and `retryIf` is guarded, so a
  throwing/rejecting hook can never mask the real error or abort the retry loop.
- **Validation:** `RetryPolicy` rejects `maxAttempts < 1` at runtime (not only via
  `assert`, which is stripped in release).
- Jitter is applied after the `maxDelay` clamp (so the capped tail still varies),
  `Random` is instantiated once, and duplicate policy types in a `PolicyBuilder`
  now throw instead of sorting non-deterministically.
- `TimeoutPolicy.execute` is `async`, so a synchronous throw from the action
  surfaces as a `Future` error rather than escaping synchronously.

### Added
- **`CancellationToken`** — pass to `.retry(cancelToken: …)` to abort further
  attempts *and* interrupt a backoff that is already sleeping (e.g. from a
  widget's `dispose`). Also `shouldContinue` — a cheap pre-backoff gate.
- **Observability:** `onRetry(error, attempt, delay)`, circuit-breaker
  `onStateChange(from, to)`, and read-only `state` / `failureCount` getters.

### Changed (breaking)
- `PolicyBuilder.fallback` / `FallbackPolicy.fallback` take
  `Future<T> Function(Object error)` (the error is passed in) — migrate
  `() async => x` to `(_) async => x`.
- `CircuitBreakerPolicy` open state throws `CircuitOpenException`, not `StateError`.
- A `PolicyBuilder` accepts at most one policy of each type.

### Notes
- Composition order is fixed (`Fallback → CircuitBreaker → Retry → Timeout`):
  timeout is per-attempt, breaker is outside retry. Reuse ONE builder per endpoint
  so the breaker accumulates state (a builder rebuilt per call never trips).
- Full pre-release review: `docs/code-review-2026-07-21.md`.

## [0.1.0] - 2025-07-06
### Added
- Initial release of execution_policy package
- RetryPolicy with fixed, linear, exponential, and jitter-ed backoff strategies
- TimeoutPolicy to enforce timeouts on async operations
- FallbackPolicy for fallback handling
- CircuitBreakerPolicy to prevent repeated failures
- PolicyBuilder for fluent chaining of policies
- PolicyDebugger for tracing and logging policy execution
- 
## [0.1.1] – 2025-07-06
### Changed
- Added dartdoc for `Policy.execute(...)` in `interface.dart`
- Documented `CircuitBreakerPolicy.execute` and constructors
- Documented `FallbackPolicy` and its `execute` method

## [0.2.0] - 2025-07-06
### Added
- Added `reset()` method to `PolicyBuilder<T>` for clearing all policies.
- Added `copy()` method to `PolicyBuilder<T>` for copying all policies.
