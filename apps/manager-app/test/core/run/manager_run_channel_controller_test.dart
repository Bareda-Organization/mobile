import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 소켓 없이 [ManagerRunChannelController] 의 반응만 보려는 가짜 클라이언트 — 컨트롤러가 쓰는 입구만 구현하고
/// 나머지는 쓰이면 시험이 실패하게 둔다.
class _FakeClient implements BaraedaWebSocketClient {
  final _state = StreamController<WsConnectionState>.broadcast();
  final _forbidden = StreamController<String>.broadcast();
  final _expired = StreamController<void>.broadcast();
  void Function(WebSocketEnvelope)? onEnvelope;
  int reconnectNowCalls = 0;

  @override
  Stream<WsConnectionState> get connectionState => _state.stream;

  @override
  Stream<String> get forbiddenSubscriptions => _forbidden.stream;

  @override
  Stream<void> get sessionExpired => _expired.stream;

  @override
  void connect() {}

  @override
  void reconnectNow() => reconnectNowCalls++;

  @override
  void disconnect() {}

  @override
  void dispose() {}

  @override
  void Function({Map<String, String>? unsubscribeHeaders}) subscribe(
    String destination,
    void Function(WebSocketEnvelope envelope) onEnvelope,
  ) {
    this.onEnvelope = onEnvelope;
    return ({Map<String, String>? unsubscribeHeaders}) {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 시험의 관심사가 아니다: ${invocation.memberName}');

  /// 서버가 `connected` 를 알린 것처럼 — 컨트롤러가 이때 구독을 건다.
  void emitConnected() => _state.add(WsConnectionState.connected);

  /// 같은 회차의 이벤트가 방송으로 온 것처럼.
  void emitEvent(WsEventType event) => onEnvelope!(
    WebSocketEnvelope(
      event: event,
      eventWireValue: event.wireValue,
      runId: 'run-1',
      occurredAt: DateTime(2026, 10, 1, 8),
      payload: const {},
    ),
  );
}

/// 어떤 화면 값이 몇 번 새로 읽혔는지 세는 묶음 — 이벤트가 오면 컨트롤러가 이 provider 들을 무효화한다.
class _Loads {
  int roster = 0;
  int driveRoster = 0;
  int route = 0;
  int todayRuns = 0;
}

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

Future<_FakeClient> _pumpController(WidgetTester tester, _Loads loads) async {
  final client = _FakeClient();
  final provider =
      StateNotifierProvider.autoDispose<
        ManagerRunChannelController,
        ManagerChannelStatus
      >((ref) => ManagerRunChannelController(ref, 'run-1', client: client));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rosterProvider.overrideWith((ref) async {
          loads.roster++;
          return _emptyRoster;
        }),
        driveModeRosterProvider.overrideWith((ref) async {
          loads.driveRoster++;
          return _emptyRoster;
        }),
        routeProvider.overrideWith((ref) async {
          loads.route++;
          throw StateError('노선은 이 시험의 관심사가 아니다');
        }),
        todayRunsProvider.overrideWith((ref) async {
          loads.todayRuns++;
          return const [];
        }),
      ],
      // 네 값을 계속 읽는 화면이 있는 것처럼 — 무효화되면 곧바로 다시 읽힌다.
      child: Consumer(
        builder: (context, ref, _) {
          ref
            ..watch(provider)
            ..watch(rosterProvider)
            ..watch(driveModeRosterProvider)
            ..watch(routeProvider)
            ..watch(todayRunsProvider);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  client.emitConnected();
  await tester.pump();
  return client;
}

void main() {
  // S-5 ② — 앱이 백그라운드에서 돌아오면 소켓도 다시 붙는다. 지금까지는 REST 만 다시 읽어서, 끊긴 연결이
  // 다음 재연결 타이머(최대 30초)를 기다렸다.
  testWidgets('앱이 백그라운드에서 돌아오면 끊긴 연결을 바로 다시 붙인다', (tester) async {
    final loads = _Loads();
    final client = await _pumpController(tester, loads);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    expect(client.reconnectNowCalls, 0);

    container.read(appResumedProvider.notifier).state++;
    await tester.pump();

    expect(client.reconnectNowCalls, 1);
  });

  // L4 — 한 방송마다 명단·노선을 바로 다시 받으면, 한 정류장에서 승차가 몰릴 때 탭마다 같은 조회가 연달아 나간다.
  group('이벤트 뒤 화면 값 재조회', () {
    testWidgets('이벤트가 몰려도 첫 이벤트 1초 뒤 한 번만 다시 읽는다', (tester) async {
      final loads = _Loads();
      final client = await _pumpController(tester, loads);
      final before = (loads.roster, loads.driveRoster, loads.route);

      client.emitEvent(WsEventType.riderChanged);
      await tester.pump(const Duration(milliseconds: 400));
      client.emitEvent(WsEventType.riderChanged);
      await tester.pump(const Duration(milliseconds: 400));
      client.emitEvent(WsEventType.stopArrived);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (loads.roster, loads.driveRoster, loads.route),
        before,
        reason: '1초가 되기 전에는 다시 읽지 않는다',
      );

      // 첫 이벤트로부터 1초 — 마지막 이벤트 기준으로 밀리면(0.9초 지점의 이벤트로 1.9초) 여기서 실패한다.
      await tester.pump(const Duration(milliseconds: 200));
      expect(loads.roster, before.$1 + 1);
      expect(loads.driveRoster, before.$2 + 1);
      expect(loads.route, before.$3 + 1);

      await tester.pump(const Duration(seconds: 3));
      expect(loads.roster, before.$1 + 1, reason: '이벤트가 더 없으면 더 읽지 않는다');
    });

    testWidgets('1초 넘게 떨어진 이벤트는 각각 다시 읽는다', (tester) async {
      final loads = _Loads();
      final client = await _pumpController(tester, loads);
      final before = loads.roster;

      client.emitEvent(WsEventType.riderChanged);
      await tester.pump(const Duration(milliseconds: 1100));
      client.emitEvent(WsEventType.riderChanged);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(loads.roster, before + 2);
    });

    testWidgets('운행 시작·종료는 회차 목록을 바로 다시 읽는다 — 기다리는 것은 명단·노선뿐이다', (
      tester,
    ) async {
      final loads = _Loads();
      final client = await _pumpController(tester, loads);
      final before = loads.todayRuns;

      client.emitEvent(WsEventType.runStarted);
      await tester.pump();

      expect(loads.todayRuns, before + 1);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
