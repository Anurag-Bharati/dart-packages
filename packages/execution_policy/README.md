# execution_policy

A Dart resilience and transient-fault-handling library inspired by C# Polly, with built-in hooks for APM error logging.

[![pub package](https://img.shields.io/pub/v/execution_policy.svg)](https://pub.dev/packages/execution_policy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

- **Retry** with fixed, linear, exponential, and jitter-ed backoff
- **Timeout** to fail long-running operations (per attempt)
- **Fallback** to recover gracefully — catches `Exception`s only, so bugs stay visible
- **Circuit Breaker** to stop hammering failing services (single-probe half-open)
- **Cancellation** via `CancellationToken` — aborts further attempts *and* a sleeping backoff
- **Fluent** `PolicyBuilder<T>` API for composition
- **PolicyDebugger** for tracing start/success/failure of each policy
- **Observability** hooks: `onError`, `onRetry`, and breaker `onStateChange`

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  execution_policy: ^0.3.0
```

## Quick Start

### Fluent Builder

Build **one long-lived builder per endpoint** and reuse it, so the circuit
breaker (and any cancel token) keep their state across calls:

```dart
final _policy = PolicyBuilder<String>()
    .retry(
      RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
      retryIf: (error) => error is HttpException,
      onRetry: (error, attempt, delay) =>
          log('retry #$attempt in ${delay.inMilliseconds}ms'),
      onError: (error, stack, attempt) async {
        // Awaited defensively — a throwing hook can't derail the retry loop.
        // e.g. FirebaseCrashlytics.instance.recordError(error, stack);
      },
    )
    .timeout(const Duration(seconds: 2)) // per-attempt deadline
    .circuitBreaker(
      failureThreshold: 3,
      resetTimeout: const Duration(seconds: 10),
      onStateChange: (from, to) => log('circuit $from -> $to'),
    )
    .fallback((error) async => 'default value'); // receives the error

Future<String> fetchWithResilience() =>
    _policy.execute(() => httpClient.get('https://example.com').then((r) => r.body));
```

### Composition order

Policies are applied by a fixed order regardless of the order you add them:

`Fallback` (outermost) → `CircuitBreaker` → `Retry` → `Timeout` (innermost).

Two consequences are intentional:

- the **timeout is per attempt** — each retry gets a fresh deadline (not a
  whole-execution budget); and
- the **breaker sits outside retry** — a single `execute` can record up to
  `maxAttempts` failures against it, so size `failureThreshold` accordingly.

### Cancellation

`retryIf`/`shouldContinue` stop *future* attempts; a `CancellationToken` also
interrupts a backoff that is already sleeping:

```dart
final token = CancellationToken();
final future = _policy.copy() // copy shares the breaker; adds a per-call token
    .reset()
    .retry(RetryOptions.exponentialJitter, cancelToken: token)
    .execute(fetch);

// later, e.g. in a widget's dispose():
token.cancel(); // aborts the in-flight backoff and stops retrying
```

### Debug Execution

```dart
final result = await _policy.debugExecute(
  () async => unreliableOperation(),
  developer.log, // any void Function(String)
);
```

## API Reference

- **PolicyBuilder\<T\>**
  - `.retry(RetryOptions options, {retryIf, shouldContinue, cancelToken, onError, onRetry})`
  - `.timeout(Duration duration)`
  - `.circuitBreaker({failureThreshold, resetTimeout, onStateChange})`
  - `.fallback(FallbackFunction<T> fallbackFn, {shouldHandle})`
  - `.execute(FutureFunction<T> action)` / `.debugExecute(action, logger)`
  - `.reset()` / `.copy()` (copy shares stateful policy instances)
  - Adding two policies of the same type throws `StateError`.

- **RetryOptions** — presets `fixed`, `linear`, `exponential`, `exponentialJitter`;
  `.copyWith(...)`; `.delayFor(int attempt) -> Duration` (overflow-safe, capped by `maxDelay`).

- **CancellationToken** — `cancel()`, `isCancelled`, `whenCancelled`.

- **CircuitBreakerPolicy\<T\>** — `state`, `failureCount`; throws `CircuitOpenException(retryAfter)` when open.

- **TimeoutPolicy\<T\>**, **FallbackPolicy\<T\>**, **PolicyDebugger\<T\>**

## Contributing
1. Fork the repo
2. Create a branch (`git checkout -b feature/foo`)
3. Commit your changes (`git commit -am 'Add foo'`)
4. Push (`git push origin feature/foo`)
5. Open a PR

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
