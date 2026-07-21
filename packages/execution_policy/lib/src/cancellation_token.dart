import 'dart:async';

/// A one-shot signal used to abort an in-flight policy execution — including a
/// backoff delay that is already sleeping.
///
/// Complete it once (for example from a widget's `dispose`) to stop further
/// retries and interrupt any pending backoff. Cancellation is terminal: a token
/// cannot be un-cancelled or reused.
///
/// ```dart
/// final token = CancellationToken();
/// // ...later, when the caller goes away:
/// token.cancel();
/// ```
class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// Completes as soon as the token is cancelled; never completes otherwise.
  ///
  /// Race this against a delay to interrupt it the moment cancellation occurs.
  Future<void> get whenCancelled => _completer.future;

  /// Requests cancellation. Idempotent — repeat calls are ignored.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
