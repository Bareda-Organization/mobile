import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 지도 오버레이 동기화가 겹쳐 돌지 않는지 — 겹치면 같은 승하차지 핀 이미지를 두 번 동시에 만들다
/// 빈 이미지 파일이 생기고, 네이버 SDK(iOS)가 그 파일을 읽다 앱이 종료된다(2026-09-30 시뮬레이터 실측).
void main() {
  test('실행 중에 들어온 요청은 겹쳐 돌지 않고, 끝난 뒤 한 번만 다시 돈다', () async {
    var running = 0;
    var maxRunning = 0;
    var runs = 0;
    final gates = <Completer<void>>[];
    final sync = SerialSync(() async {
      running++;
      runs++;
      if (running > maxRunning) maxRunning = running;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      running--;
    });

    final first = sync.request();
    await Future<void>.delayed(Duration.zero);
    // 첫 실행이 끝나기 전에 요청 3번 — 버스 좌표가 2초마다 바뀌며 화면이 다시 그려지는 상황.
    unawaited(sync.request());
    unawaited(sync.request());
    unawaited(sync.request());
    await Future<void>.delayed(Duration.zero);
    expect(maxRunning, 1);
    expect(runs, 1);

    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(runs, 2, reason: '밀린 요청들은 한 번의 재실행으로 합쳐진다');
    gates[1].complete();
    await first;
    expect(maxRunning, 1);
    expect(runs, 2);
  });
}
