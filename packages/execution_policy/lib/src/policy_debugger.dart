import 'package:execution_policy/src/interface.dart';

/// A generic debugger that can wrap *any* Policy<T> and
/// emit start/done/failure logs with timings.
class PolicyDebugger<T> implements Policy<T> {
  @override
  int get order => 0;
  final Policy<T> _inner;
  final void Function(String) _logger;

  PolicyDebugger(this._inner, this._logger);

  @override
  Future<T> execute(FutureFunction<T> action) async {
    final name = _inner.runtimeType;
    _logger("[$name] → Starting");
    final sw = Stopwatch()..start();
    try {
      final result = await _inner.execute(action);
      sw.stop();
      _logger("[$name] ✓ Succeeded in ${sw.elapsedMilliseconds}ms");
      return result;
    } catch (e, _) {
      sw.stop();
      _logger("[$name] ✗ Failed in ${sw.elapsedMilliseconds}ms: $e");
      rethrow;
    }
  }
}
