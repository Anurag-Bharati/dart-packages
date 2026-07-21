import 'package:execution_policy/src/interface.dart';

/// Produces a fallback value from the [error] that triggered it.
typedef FallbackFunction<T> = Future<T> Function(Object error);

/// A fallback policy that substitutes a value when the wrapped action (or an
/// inner policy) throws.
///
/// It catches only [Exception]s: programming errors ([Error] subtypes such as
/// `TypeError`, `StateError`, `RangeError`) propagate, so genuine bugs stay
/// visible instead of being silently masked by the fallback. Narrow further
/// with [shouldHandle].
///
/// Use this as the outermost policy to always return something meaningful even
/// when the other policies fail.
class FallbackPolicy<T> implements Policy<T> {
  @override
  int get order => 1;

  /// Produces the fallback value; receives the error that triggered it.
  final FallbackFunction<T> fallback;

  /// Optional predicate: return `false` to rethrow instead of falling back.
  final bool Function(Object error)? shouldHandle;

  /// Creates a [FallbackPolicy] that invokes [fallback] on a handled error.
  const FallbackPolicy({required this.fallback, this.shouldHandle});

  @override
  Future<T> execute(FutureFunction<T> action) async {
    try {
      return await action();
    } on Exception catch (error) {
      if (!(shouldHandle?.call(error) ?? true)) rethrow;
      return await fallback(error);
    }
  }
}
