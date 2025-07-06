# execution_policy

A Dart resilience and transient-fault-handling library inspired by C# Polly, with built-in hooks for APM error logging.

[![pub package](https://img.shields.io/pub/v/execution_policy.svg)](https://pub.dev/packages/execution_policy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

- **Retry** with fixed, linear, exponential, and jitter-ed backoff
- **Timeout** to abort long-running operations
- **Fallback** to recover gracefully from failures
- **Circuit Breaker** to stop hammering failing services
- **Fluent** `PolicyBuilder<T>` API for composition
- **PolicyDebugger** for tracing start/success/failure of each policy
- **APM-friendly** `onError` hooks for integrating with observability tools

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  execution_policy:
```

## Quick Start

### Fluent Builder

```dart
Future<String> fetchWithResilience() async {
  return await PolicyBuilder<String>()
      .retry(
    RetryOptions.exponentialJitter.copyWith(maxAttempts: 4),
    retryIf: (error) => error is HttpException,
    onError: (error, stack, attempt) async {
      // Send to your APM or logging system:
      // Example usecase for Firebase Crashlytics
      // _crashlytics.recordError(error, stack, information: ["Failed attempt $attempt"]);
    },
  )
      .timeout(Duration(seconds: 2))
      .circuitBreaker(
    failureThreshold: 3,
    resetTimeout: Duration(seconds: 10),
  )
      .fallback(() async => 'default value')
      .execute(() async {
    // Your unstable operation:
    return await httpClient.get('https://example.com').then((r) => r.body);
  });
}
```


### Debug Execution

```dart
import 'dart:developer' as developer show log;
import 'package:execution_policy/execution_policy.dart';

void main () async {
  final debugResult = await PolicyBuilder<String>()
      .retry(RetryOptions.fixed)
      .timeout(Duration(seconds: 1))
      .debugExecute(
        () async => unreliableOperation(),
    developer.log, // attach debug logger like log or print
  );
}
```



## API Reference

- **PolicyBuilder<T>**
    - `.retry(RetryOptions options, {bool Function(Object)? retryIf, Future<void> Function(Object, StackTrace?, int)? onError})`
    - `.timeout(Duration duration)`
    - `.circuitBreaker({int failureThreshold, Duration resetTimeout})`
    - `.fallback(FutureFunction<T> fallbackFn)`
    - `.execute(FutureFunction<T> action)`
    - `.debugExecute(FutureFunction<T> action, void Function(String) logger)`

- **RetryOptions**
    - Presets: `fixed`, `linear`, `exponential`, `exponentialJitter`
    - `.copyWith({int? maxAttempts, Duration? baseDelay, RetryDelayType? delayType, double? jitterFactor, Duration? maxDelay})`
    - `.delayFor(int attempt) -> Duration`

- **TimeoutPolicy<T>**
- **FallbackPolicy<T>**
- **CircuitBreakerPolicy<T>**
- **PolicyDebugger<T>**

## Contributing
1. Fork the repo
2. Create a branch (`git checkout -b feature/foo`)
3. Commit your changes (`git commit -am 'Add foo'`)
4. Push (`git push origin feature/foo`)
5. Open a PR

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
