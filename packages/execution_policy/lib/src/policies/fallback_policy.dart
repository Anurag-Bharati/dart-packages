import 'package:execution_policy/src/interface.dart';

class FallbackPolicy<T> implements Policy<T> {
  @override
  int get order => 1;
  final FutureFunction<T> fallback;

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
