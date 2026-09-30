import 'dart:math';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `nextDouble()` 을 고정값으로 돌려주는 난수 — 지터 범위를 정확히 재기 위한 가짜.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}

void main() {
  group('WsBackoffPolicy — Timer 없이 순수 계산만 검사', () {
    const policy = WsBackoffPolicy();

    test('기본 정책은 1·2·4·8·16·30(상한) 초로 증가한다', () {
      expect(policy.delayFor(1), const Duration(seconds: 1));
      expect(policy.delayFor(2), const Duration(seconds: 2));
      expect(policy.delayFor(3), const Duration(seconds: 4));
      expect(policy.delayFor(4), const Duration(seconds: 8));
      expect(policy.delayFor(5), const Duration(seconds: 16));
      expect(policy.delayFor(6), const Duration(seconds: 30));
    });

    test('상한(30초)을 넘는 시도도 30초로 고정된다', () {
      expect(policy.delayFor(7), const Duration(seconds: 30));
      expect(policy.delayFor(20), const Duration(seconds: 30));
    });

    test('maxAttempts(기본 6)를 넘긴 시도는 포기 대상이다', () {
      expect(policy.shouldGiveUp(6), isFalse);
      expect(policy.shouldGiveUp(7), isTrue);
    });

    test('초기값을 바꾸면 그 값 기준으로 배수가 붙는다', () {
      const custom = WsBackoffPolicy(
        initialDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 5),
        multiplier: 3,
        maxAttempts: 2,
      );
      expect(custom.delayFor(1), const Duration(milliseconds: 500));
      expect(custom.delayFor(2), const Duration(milliseconds: 1500));
      // 3차: 500*9=4500ms, 아직 5000ms 상한 아래.
      expect(custom.delayFor(3), const Duration(milliseconds: 4500));
      // 4차: 500*27=13500ms → 5000ms 로 절단.
      expect(custom.delayFor(4), const Duration(seconds: 5));
      expect(custom.shouldGiveUp(2), isFalse);
      expect(custom.shouldGiveUp(3), isTrue);
    });

    test('지터는 대기를 줄이는 방향으로만 더해져 상한을 넘지 않는다 — 한꺼번에 끊긴 앱들이 같은 초에 붙지 않게', () {
      // F07-13(c) — 서버 재배포로 모든 앱이 동시에 끊기면 고정 간격은 같은 순간에 몰린다.
      // 난수 0 → 원래 간격, 난수 1 미만 끝 → 간격의 (1 - jitterRatio) 배.
      final full = policy.jitteredDelayFor(3, _FixedRandom(0));
      final least = policy.jitteredDelayFor(3, _FixedRandom(1));

      expect(full, policy.delayFor(3));
      expect(
        least.inMilliseconds,
        (policy.delayFor(3).inMilliseconds * (1 - policy.jitterRatio)).round(),
      );
      expect(least, lessThan(full));
      // 상한에 닿은 회차도 상한을 넘지 않는다.
      expect(
        policy.jitteredDelayFor(6, _FixedRandom(0)),
        lessThanOrEqualTo(policy.maxDelay),
      );
    });
  });
}
