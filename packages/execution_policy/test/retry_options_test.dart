import 'dart:math';

import 'package:execution_policy/execution_policy.dart';
import 'package:test/test.dart';

void main() {
  group('RetryOptions.delayFor', () {
    test('fixed preset always returns baseDelay', () {
      final opts = RetryOptions.fixed;
      for (var i = 1; i <= 10; i++) {
        expect(
          opts.delayFor(i),
          equals(opts.baseDelay),
          reason: 'fixed delay should always be baseDelay',
        );
      }
    });

    test('linear preset scales linearly', () {
      final opts = RetryOptions.linear; // baseDelay=200ms, linear
      for (var i = 1; i <= 5; i++) {
        final expectedMs = 200 * i;
        expect(
          opts.delayFor(i).inMilliseconds,
          expectedMs,
          reason: 'linear: attempt $i → ${expectedMs}ms',
        );
      }
    });

    test('exponential preset doubles each time', () {
      final opts = RetryOptions.exponential; // baseDelay=200ms, exponential
      for (var i = 1; i <= 5; i++) {
        final expectedMs = 200 * pow(2, i - 1).toInt();
        expect(
          opts.delayFor(i).inMilliseconds,
          expectedMs,
          reason: 'exponential: attempt $i → ${expectedMs}ms',
        );
      }
    });

    test('exponentialJitter preset is within ±jitterFactor', () {
      final opts = RetryOptions.exponentialJitter; // jitterFactor=0.25
      for (var i = 1; i <= 5; i++) {
        final baseMs = 200 * pow(2, i - 1).toInt();
        // run multiple times to sample random jitter
        for (var sample = 0; sample < 10; sample++) {
          // temporarily override Random() inside the method:
          // — since we can’t inject our rnd, we just check the range:
          final actual = opts.delayFor(i).inMilliseconds;
          final minMs = (baseMs * (1 - opts.jitterFactor)).round();
          final maxMs = (baseMs * (1 + opts.jitterFactor)).round();
          expect(
            actual,
            inInclusiveRange(minMs, maxMs),
            reason: 'jittered: attempt $i → $actual ms (expected between $minMs and $maxMs)',
          );
        }
      }
    });

    test('delay is capped by maxDelay', () {
      final opts = RetryOptions.exponential.copyWith(
        maxDelay: Duration(milliseconds: 500),
      );
      // 2^(10-1)*200ms = 200 * 512 = 102400ms → capped to 500ms
      expect(opts.delayFor(10), equals(Duration(milliseconds: 500)));
    });

    test('zero or negative attempts treated as zero delay', () {
      final opts = RetryOptions.linear;
      expect(opts.delayFor(0), equals(Duration.zero));
      // negative not enforced by API, but we expect at least zero
      expect(opts.delayFor(-1).inMilliseconds, greaterThanOrEqualTo(0));
    });
  });
}
