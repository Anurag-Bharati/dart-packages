import 'package:execution_policy/src/interface.dart';

class TimeoutPolicy<T> implements Policy<T> {
  @override
  int get order => 4;
  final Duration timeout;

  const TimeoutPolicy(this.timeout);

  @override
  Future<T> execute(FutureFunction<T> action) {
    return action().timeout(timeout);
  }
}
