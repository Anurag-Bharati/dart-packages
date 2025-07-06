import 'package:execution_policy/src/interface.dart';

/// A fallback policy that catches any exception thrown by upstream policies
/// or the action itself, and instead returns a fallback value.
///
/// Use this as the outermost policy to ensure you always return something
/// meaningful even when all other policies fail.
class FallbackPolicy<T> implements Policy<T> {
  @override
  int get order => 1;

  /// A function that produces the fallback value when an error occurs.
  final FutureFunction<T> fallback;

  /// Creates a [FallbackPolicy] that invokes [fallback] on error.
  ///
  /// [fallback] must not be null.
  const FallbackPolicy({required this.fallback});

  @override
  Future<T> execute(FutureFunction<T> action) async {
    try {
      return await action();
    } catch (_) {
      return await fallback();
    }
  }
}
