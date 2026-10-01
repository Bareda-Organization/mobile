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

    // R46-FIXRT S-5 — 터널·음영이 1분을 넘기거나 백엔드 재기동이 길어지면
    // (`start_period 90s`) 6회(약 1분) 뒤 포기하던 연결이 끊긴 채 방치됐다.
    // 기본 정책은 포기 없이 30초 간격으로 계속 시도한다.
    test('기본 정책은 몇 번째 시도에서도 포기하지 않는다', () {
      expect(policy.shouldGiveUp(7), isFalse);
      expect(policy.shouldGiveUp(100), isFalse);
      expect(policy.shouldGiveUp(100000), isFalse);
    });

    test('상한을 준 정책은 그 횟수를 넘긴 시도를 포기 대상으로 본다', () {
      const limited = WsBackoffPolicy(maxAttempts: 6);
      expect(limited.shouldGiveUp(6), isFalse);
      expect(limited.shouldGiveUp(7), isTrue);
    });

    test('포기 없이 오래 이어져도 대기는 30초 상한 안에서 지터만 붙는다', () {
      for (final attempt in [7, 50, 1000]) {
        expect(
          policy.jitteredDelayFor(attempt, _FixedRandom(1)),
          const Duration(milliseconds: 21000),
        );
        expect(
          policy.jitteredDelayFor(attempt, _FixedRandom(0)),
          const Duration(seconds: 30),
        );
      }
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
