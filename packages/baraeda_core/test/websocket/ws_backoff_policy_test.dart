import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
