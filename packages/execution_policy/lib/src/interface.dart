typedef FutureFunction<T> = Future<T> Function();

abstract class Policy<T> {
  /// Lower `order` values wrap outermost (executed first).
  int get order;
  Future<T> execute(FutureFunction<T> action);
}
