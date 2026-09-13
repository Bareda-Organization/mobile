import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/frame_ticker.dart';

void main() {
  group('FrameTicker', () {
    test('시작하면 짧은 간격으로 콜백이 여러 번 불린다', () async {
      final ticker = FrameTicker(interval: const Duration(milliseconds: 5));
      var callCount = 0;

      ticker.start(() => callCount++);
      expect(ticker.isRunning, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      ticker.stop();

      expect(callCount, greaterThan(0));
    });

    test('stop 을 부르면 그 뒤로 더 이상 콜백이 불리지 않는다(누수 방지)', () async {
      final ticker = FrameTicker(interval: const Duration(milliseconds: 5));
      var callCount = 0;

      ticker.start(() => callCount++);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ticker.stop();

      final countAtStop = callCount;
      expect(countAtStop, greaterThan(0));
      expect(ticker.isRunning, isFalse);

      // stop 이후에도 시간이 흐르지만 콜백은 더 이상 늘지 않아야 한다 —
      // 이 검사가 실패한다는 것은 화면이 사라진 뒤에도 타이머가 계속
      // `setPosition` 을 부르는 누수가 있다는 뜻이다.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(callCount, countAtStop);
    });

    test('isRunning 은 시작·정지 상태를 그대로 반영한다', () {
      final ticker = FrameTicker(interval: const Duration(milliseconds: 5));

      expect(ticker.isRunning, isFalse);
      ticker.start(() {});
      expect(ticker.isRunning, isTrue);
      ticker.stop();
      expect(ticker.isRunning, isFalse);
    });
  });
}
