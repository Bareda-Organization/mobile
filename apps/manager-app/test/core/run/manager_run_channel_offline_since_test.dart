import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/manager_connection.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// 소켓 없이 연결 상태만 밀어 넣는 가짜 클라이언트 — 컨트롤러가 쓰는 입구만 구현한다.
class _FakeClient implements BaraedaWebSocketClient {
  final _state = StreamController<WsConnectionState>.broadcast();
  final _forbidden = StreamController<String>.broadcast();
  final _expired = StreamController<void>.broadcast();

  @override
  Stream<WsConnectionState> get connectionState => _state.stream;

  @override
  Stream<String> get forbiddenSubscriptions => _forbidden.stream;

  @override
  Stream<void> get sessionExpired => _expired.stream;

  @override
  void connect() {}

  @override
  void reconnectNow() {}

  @override
  void disconnect() {}

  @override
  void dispose() {}

  @override
  void Function({Map<String, String>? unsubscribeHeaders}) subscribe(
    String destination,
    void Function(WebSocketEnvelope envelope) onEnvelope,
  ) => ({Map<String, String>? unsubscribeHeaders}) {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 시험의 관심사가 아니다: ${invocation.memberName}');

  void emit(WsConnectionState state) => _state.add(state);
}

/// 시험이 손으로 돌리는 시계.
class _MutableClock implements Clock {
  _MutableClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

void main() {
  late _FakeClient client;
  late _MutableClock clock;
  late StateNotifierProvider<ManagerRunChannelController, ManagerChannelStatus>
  channel;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    client = _FakeClient();
    clock = _MutableClock(DateTime(2026, 10, 4, 8, 41));
    channel =
        StateNotifierProvider<
          ManagerRunChannelController,
          ManagerChannelStatus
        >((ref) => ManagerRunChannelController(ref, 'run-1', client: client));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clockProvider.overrideWithValue(clock)],
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(channel);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(Consumer)));
  }

  testWidgets('연결이 끊기면 그 시각을 기억하고 계속 끊겨 있어도 처음 시각을 지킨다', (tester) async {
    final container = await pump(tester);
    final controller = container.read(channel.notifier);
    client.emit(WsConnectionState.connected);
    await tester.pump();
    expect(controller.offlineSince, isNull, reason: '연결된 동안은 끊긴 시각이 없다');

    client.emit(WsConnectionState.reconnecting);
    await tester.pump();
    expect(controller.offlineSince, DateTime(2026, 10, 4, 8, 41));

    // 재시도 중 connecting ↔ reconnecting 을 오가도 "언제부터" 는 처음 끊긴 시각이다.
    clock.current = DateTime(2026, 10, 4, 8, 50);
    client.emit(WsConnectionState.connecting);
    await tester.pump();
    client.emit(WsConnectionState.reconnecting);
    await tester.pump();
    expect(controller.offlineSince, DateTime(2026, 10, 4, 8, 41));
  });

  testWidgets('다시 연결되면 끊긴 시각을 지운다', (tester) async {
    final container = await pump(tester);
    final controller = container.read(channel.notifier);
    client.emit(WsConnectionState.reconnecting);
    await tester.pump();
    expect(controller.offlineSince, isNotNull);

    client.emit(WsConnectionState.connected);
    await tester.pump();

    expect(controller.offlineSince, isNull);
  });

  testWidgets('처음 연결을 시도하는 중(connecting)은 끊긴 것이 아니다', (tester) async {
    final container = await pump(tester);
    final controller = container.read(channel.notifier);

    client.emit(WsConnectionState.connecting);
    await tester.pump();

    expect(controller.offlineSince, isNull);
  });
}
