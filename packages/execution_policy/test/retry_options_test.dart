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
        for (var sample = 0; sample < 10; sample++) {
          final actual = opts.delayFor(i).inMilliseconds;
          final minMs = (baseMs * (1 - opts.jitterFactor)).round();
          final maxMs = (baseMs * (1 + opts.jitterFactor)).round();
          expect(
            actual,
            inInclusiveRange(minMs, maxMs),
            reason:
                'jittered: attempt $i → $actual ms (expected $minMs..$maxMs)',
          );
        }
      }
    });

    test('delay is capped by maxDelay', () {
      final opts = RetryOptions.exponential.copyWith(
        maxDelay: Duration(milliseconds: 500),
      );
      expect(opts.delayFor(10), equals(Duration(milliseconds: 500)));
    });

    test('zero or negative attempts treated as zero delay', () {
      final opts = RetryOptions.linear;
      expect(opts.delayFor(0), equals(Duration.zero));
      expect(opts.delayFor(-1).inMilliseconds, greaterThanOrEqualTo(0));
    });

    // B1 regression: at very high attempt counts the int64 exponential curve
    // used to overflow to a NEGATIVE value that bypassed maxDelay, producing a
    // zero-delay hot loop. It must now stay clamped and non-negative forever.
    test('never overflows past maxDelay at extreme attempt counts', () {
      final opts = RetryOptions.exponential.copyWith(
        maxDelay: const Duration(seconds: 5),
      );
      for (final attempt in [56, 57, 63, 64, 65, 128, 1000]) {
        final d = opts.delayFor(attempt);
        expect(d.inMilliseconds, greaterThanOrEqualTo(0),
            reason: 'attempt $attempt must not go negative');
        expect(d, lessThanOrEqualTo(const Duration(seconds: 5)),
            reason: 'attempt $attempt must stay capped');
      }
    });

    test('jittered delay never exceeds maxDelay at the capped tail', () {
      final opts = RetryOptions.exponentialJitter.copyWith(
        maxDelay: const Duration(milliseconds: 1000),
      );
      for (var sample = 0; sample < 50; sample++) {
        expect(opts.delayFor(30),
            lessThanOrEqualTo(const Duration(milliseconds: 1000)));
      }
    });
  });
}
