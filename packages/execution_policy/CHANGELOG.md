# Changelog

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
## [0.1.1] – 2025-07-10
### Changed
- Added dartdoc for `Policy.execute(...)` in `interface.dart`
- Documented `CircuitBreakerPolicy.execute` and constructors
- Documented `FallbackPolicy` and its `execute` method
