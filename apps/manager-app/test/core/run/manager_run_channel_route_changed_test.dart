import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/domain/route_repository.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 실제 소켓 없이 구독 콜백만 붙잡아 시험이 봉투를 직접 흘려보내는 가짜 —
/// `manager_run_channel_session_expired_test.dart` 의 대역과 같은 방식이다.
class _FakeWebSocketClient extends BaraedaWebSocketClient {
  _FakeWebSocketClient()
    : super(
        url: 'ws://test',
        tokenStorage: TokenStorage(
          accessTokenKey: 'test_access',
          refreshTokenKey: 'test_refresh',
        ),
      );

  final _connectionController = StreamController<WsConnectionState>.broadcast();
  void Function(WebSocketEnvelope envelope)? onEnvelope;

  @override
  Stream<WsConnectionState> get connectionState => _connectionController.stream;

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void Function({Map<String, String>? unsubscribeHeaders}) subscribe(
    String destination,
    void Function(WebSocketEnvelope envelope) onEnvelope,
  ) {
    this.onEnvelope = onEnvelope;
    return ({Map<String, String>? unsubscribeHeaders}) {};
  }

  void emitConnected() =>
      _connectionController.add(WsConnectionState.connected);
}

/// 조회 횟수를 세고, 조회할 때마다 다음 응답을 돌려주는 대역.
class _CountingRouteRepository implements RouteRepository {
  _CountingRouteRepository(this.responses);

  final List<RouteResponse> responses;
  int fetchCount = 0;

  @override
  Future<RouteResponse> fetchRoute(String runId) async {
    final index = fetchCount < responses.length
        ? fetchCount
        : responses.length - 1;
    fetchCount++;
    return responses[index];
  }
}

class _CountingRosterRepository implements RosterRepository {
  _CountingRosterRepository(this.responses);

  final List<RosterResponse> responses;
  int fetchCount = 0;

  @override
  Future<RosterResponse> fetchRoster(String runId) async {
    final index = fetchCount < responses.length
        ? fetchCount
        : responses.length - 1;
    fetchCount++;
    return responses[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

RouteResponse _route({bool secondSkipped = false}) => RouteResponse.fromJson({
  'stops': [
    for (var seq = 1; seq <= 2; seq++)
      {
        'stop_id': 's$seq',
        'seq': seq,
        'name': '정차지$seq',
        'lat': 37.5,
        'lng': 127.0,
        if (seq == 2 && secondSkipped) 'change': 'skipped',
      },
  ],
});

RosterResponse _roster({bool secondSkipped = false}) =>
    RosterResponse.fromJson({
      'run_id': 'run-1',
      'bus_no': '3호차',
      'direction': 'to_academy',
      'counts': {'boarded': 0, 'waiting': 0, 'no_show': 0, 'absent_n': 0},
      'stops': [
        for (var seq = 1; seq <= 2; seq++)
          {
            'stop_id': 's$seq',
            'seq': seq,
            'name': '정차지$seq',
            if (seq == 2 && secondSkipped) 'change': 'skipped',
            'students': <Map<String, dynamic>>[],
          },
      ],
    });

WebSocketEnvelope _envelope(String event, String runId) =>
    WebSocketEnvelope.fromJson({
      'event': event,
      'run_id': runId,
      'occurred_at': '2026-09-30T08:00:00+09:00',
      'payload': <String, dynamic>{},
    });

/// 운행 화면이 보는 두 값(§4.3 노선 · §4.2 명단)을 유지한 채 매니저 채널로
/// 방송을 흘려, 재조회가 일어나는지·새 응답으로 바뀌는지 본다(R36-FE FE6).
void main() {
  late ProviderContainer container;
  late _FakeWebSocketClient client;
  late _CountingRouteRepository routeRepo;
  late _CountingRosterRepository rosterRepo;

  setUp(() async {
    routeRepo = _CountingRouteRepository([
      _route(),
      _route(secondSkipped: true),
    ]);
    rosterRepo = _CountingRosterRepository([
      _roster(),
      _roster(secondSkipped: true),
    ]);
    client = _FakeWebSocketClient();
    container = ProviderContainer(
      overrides: [
        routeRepositoryProvider.overrideWithValue(routeRepo),
        rosterRepositoryProvider.overrideWithValue(rosterRepo),
      ],
    );
    addTearDown(container.dispose);

    container.read(selectedRunIdProvider.notifier).state = 'run-1';
    // 운행 화면이 떠 있는 동안 두 값을 계속 보고 있는 것과 같다(명단 화면은 동시에 안 뜬다).
    container
      ..listen(routeProvider, (_, _) {})
      ..listen(driveModeRosterProvider, (_, _) {});
    await container.read(routeProvider.future);
    await container.read(driveModeRosterProvider.future);

    late Ref capturedRef;
    final probe = Provider<void>((ref) => capturedRef = ref);
    container.read(probe);
    final controller = ManagerRunChannelController(
      capturedRef,
      'run-1',
      client: client,
    );
    addTearDown(controller.dispose);
    client.emitConnected();
    await Future<void>.delayed(Duration.zero);
    expect(client.onEnvelope, isNotNull, reason: '연결되면 채널을 구독해야 한다');
  });

  Future<void> receive(WebSocketEnvelope envelope) async {
    client.onEnvelope!(envelope);
    await Future<void>.delayed(Duration.zero);
  }

  test('route_changed 방송 → 노선·명단을 다시 불러와 새 응답(한 곳 skipped)으로 바뀐다', () async {
    expect(routeRepo.fetchCount, 1);
    expect(rosterRepo.fetchCount, 1);

    await receive(_envelope('route_changed', 'run-1'));
    final route = await container.read(routeProvider.future);
    final roster = await container.read(driveModeRosterProvider.future);

    expect(routeRepo.fetchCount, 2);
    expect(rosterRepo.fetchCount, 2);
    expect(route.stops[1].change, RouteStopChange.skipped);
    expect(roster.stops[1].change, StopChange.skipped);
    expect(nextUnarrivedStop(roster)!.stopId, 's1');
  });

  test('다른 회차의 route_changed 방송은 무시 — 조회 요청 0', () async {
    await receive(_envelope('route_changed', 'run-2'));

    expect(routeRepo.fetchCount, 1);
    expect(rosterRepo.fetchCount, 1);
  });

  test('rider_changed 방송(③구간 미등원 — stop_skipped) → 같은 재조회 경로를 탄다', () async {
    await receive(_envelope('rider_changed', 'run-1'));
    final roster = await container.read(driveModeRosterProvider.future);

    expect(routeRepo.fetchCount, 2);
    expect(rosterRepo.fetchCount, 2);
    expect(roster.stops[1].change, StopChange.skipped);
  });
}
