import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/refresh/visible_poller.dart';

/// R46 C(D #7) — 주기 갱신은 앱이 보이는 동안만 돈다. 백그라운드 · 다른 화면이 위에 있을 때는 멈추고,
/// 앱이 앞으로 돌아오면 즉시 한 번 받는다.
void main() {
  const interval = Duration(seconds: 90);

  testWidgets('간격이 지나기 전에는 받지 않고, 지나면 한 번 받는다', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(interval: interval, onTick: () => ticks++)
      ..start();

    await tester.pump(const Duration(seconds: 89));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    poller.dispose();
  });

  testWidgets('백그라운드에서는 멈추고 앞으로 돌아오면 즉시 한 번 받는다', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(interval: interval, onTick: () => ticks++)
      ..start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 300));
    expect(ticks, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(ticks, 1);
    poller.dispose();
  });

  testWidgets('백그라운드를 거치지 않은 inactive→resumed 는 다시 받지 않는다', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(interval: interval, onTick: () => ticks++)
      ..start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(ticks, 0);
    poller.dispose();
  });

  testWidgets('다른 화면이 위에 있는 동안은 멈춘다', (tester) async {
    var ticks = 0;
    var covered = true;
    final poller = VisiblePoller(
      interval: interval,
      onTick: () => ticks++,
      isCovered: () => covered,
    )..start();

    await tester.pump(const Duration(seconds: 180));
    expect(ticks, 0);

    covered = false;
    await tester.pump(interval);
    expect(ticks, 1);
    poller.dispose();
  });
}
