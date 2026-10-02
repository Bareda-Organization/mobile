import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/network/offline_bar.dart';

/// R46 B2 #22 — 연결이 끊기면 카드마다 오류 띠를 나열하지 않고 화면 맨 위 한 줄로 알린다.
/// 판정은 `connectivity_plus` 가 아니라 요청 결과다 — 기기가 와이파이에 붙어 있어도 서버에 못 닿는 경우
/// (음영 구간·서버 중단)를 앞의 방식은 잡지 못한다.
class _Adapter implements HttpClientAdapter {
  new(this.respond);

  Future<ResponseBody> Function() respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond();

  @override
  void close({bool force = false}) {}
}

class _MutableClock implements Clock {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

ResponseBody _status(int code) => ResponseBody.fromString('{}', code);

void main() {
  group('NetworkStatusInterceptor', () {
    late ProviderContainer container;
    late _MutableClock clock;
    late _Adapter adapter;
    late Dio dio;

    setUp(() {
      clock = _MutableClock(DateTime(2026, 9, 12, 7, 31));
      container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(clock)],
      );
      addTearDown(container.dispose);
      adapter = _Adapter(() async => _status(200));
      dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(
          NetworkStatusInterceptor(
            onReachable: () =>
                container.read(networkStatusProvider.notifier).markReachable(),
            onUnreachable: () => container
                .read(networkStatusProvider.notifier)
                .markUnreachable(),
          ),
        );
    });

    NetworkStatus status() => container.read(networkStatusProvider);

    test('요청이 성공하면 연결 중이고 그 시각을 마지막 갱신으로 기억한다', () async {
      await dio.get<dynamic>('http://x/ok');

      expect(status().isOffline, isFalse);
      expect(status().lastReachableAt, DateTime(2026, 9, 12, 7, 31));
    });

    test('연결 실패·시간 초과는 끊김이다 — 마지막 갱신 시각은 그대로 남는다', () async {
      await dio.get<dynamic>('http://x/ok');
      clock.value = DateTime(2026, 9, 12, 7, 40);
      adapter.respond = () => throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );

      await expectLater(
        dio.get<dynamic>('http://x/down'),
        throwsA(isA<DioException>()),
      );

      expect(status().isOffline, isTrue);
      expect(status().lastReachableAt, DateTime(2026, 9, 12, 7, 31));
    });

    test('서버가 4xx·5xx 로 답했으면 서버에는 닿은 것이다 — 끊김이 아니다', () async {
      adapter.respond = () async => _status(503);
      await expectLater(
        dio.get<dynamic>('http://x/err'),
        throwsA(isA<DioException>()),
      );

      expect(status().isOffline, isFalse);
    });

    test('끊긴 뒤 다음 요청이 성공하면 다시 연결 중이다', () async {
      adapter.respond = () => throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      await expectLater(
        dio.get<dynamic>('http://x/down'),
        throwsA(isA<DioException>()),
      );
      expect(status().isOffline, isTrue);

      adapter.respond = () async => _status(200);
      await dio.get<dynamic>('http://x/ok');
      expect(status().isOffline, isFalse);
    });
  });

  group('OfflineBar', () {
    Future<void> pump(WidgetTester tester, NetworkStatus status) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkStatusProvider.overrideWith(
              (ref) => NetworkStatusNotifier(initial: status),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OfflineBar())),
        ),
      );
    }

    testWidgets('연결 중이면 아무것도 그리지 않는다', (tester) async {
      await pump(tester, const NetworkStatus());
      expect(find.textContaining('연결'), findsNothing);
    });

    testWidgets('끊기면 한 줄로 알리고 마지막 갱신 시각을 기기 표준시로 보인다', (tester) async {
      final reachable = DateTime.utc(2026, 9, 12, 7, 31);
      await pump(
        tester,
        NetworkStatus(isOffline: true, lastReachableAt: reachable),
      );

      final local = reachable.toLocal();
      final hhmm = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
      expect(
        find.text('네트워크 연결이 끊겼습니다 · 마지막 갱신 $hhmm'),
        findsOneWidget,
      );
    });

    testWidgets('한 번도 닿은 적이 없으면 시각 없이 알린다', (tester) async {
      await pump(tester, const NetworkStatus(isOffline: true));
      expect(find.text('네트워크 연결이 끊겼습니다'), findsOneWidget);
    });
  });
}
