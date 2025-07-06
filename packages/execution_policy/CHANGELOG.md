<!-- CHANGELOG.md -->
# Changelog

## [0.1.0] - 2025-07-06
### Added
- Initial release of execution_policy package
- RetryPolicy with fixed, linear, exponential, and jittered backoff strategies
- TimeoutPolicy to enforce timeouts on async operations
- FallbackPolicy for fallback handling
- CircuitBreakerPolicy to prevent repeated failures
- PolicyBuilder for fluent chaining of policies
- PolicyDebugger for tracing and logging policy execution
