import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';

/// SE — 공유 패키지 C1 이 낸 `BaraedaWebSocketClient.sessionExpired` 를
/// [RouterRefreshNotifier] 가 구독해 REST 로그인 만료와 같은 경로
/// (`applyRoleAndStatus(..., role: null, status: null)` — `signOut()` 의
/// 실패 경로가 이미 쓰는 것과 같은 함수)로 보내는지 검사한다. 역할·상태가
/// 비면 `router.dart` 의 redirect 가 로그인 화면으로 보낸다(같은 판정
/// 한 곳, `sign_out_test.dart` 와 같은 전제).
class _FakeWsClient extends BaraedaWebSocketClient {
  _FakeWsClient()
    : super(
        url: 'ws://test.invalid/ws/location',
        tokenStorage: TokenStorage(
          accessTokenKey: 'se-test-access',
          refreshTokenKey: 'se-test-refresh',
        ),
      );

  final _sessionExpiredController = StreamController<void>.broadcast();

  @override
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  void emitSessionExpired() => _sessionExpiredController.add(null);

  @override
  void dispose() {
    unawaited(_sessionExpiredController.close());
  }
}

void main() {
  test('WS 세션이 만료되면(sessionExpired) 역할·상태를 비운다', () async {
    final wsClient = _FakeWsClient();
    final container = ProviderContainer(
      overrides: [webSocketClientProvider.overrideWithValue(wsClient)],
    );
    addTearDown(container.dispose);

    container.read(currentUserRoleProvider.notifier).state = UserRole.parent;
    container.read(currentAccountStatusProvider.notifier).state =
        AccountStatus.active;

    // RouterRefreshNotifier 를 만들어 구독을 건다 — 실제 앱에서는
    // `routerProvider` 가 `routerRefreshNotifierProvider` 를 watch 하는
    // 시점에 만들어진다.
    container.read(routerRefreshNotifierProvider);

    // 지금 코드는 이 스트림을 구독하지 않아 아무 일도 없어야 한다(RED).
    wsClient.emitSessionExpired();
    await pumpEventQueue();

    expect(container.read(currentUserRoleProvider), isNull);
    expect(container.read(currentAccountStatusProvider), isNull);
  });

  test('WS 세션 만료 전에는 역할·상태가 그대로다', () async {
    final wsClient = _FakeWsClient();
    final container = ProviderContainer(
      overrides: [webSocketClientProvider.overrideWithValue(wsClient)],
    );
    addTearDown(container.dispose);

    container.read(currentUserRoleProvider.notifier).state = UserRole.parent;
    container.read(currentAccountStatusProvider.notifier).state =
        AccountStatus.active;
    container.read(routerRefreshNotifierProvider);

    expect(container.read(currentUserRoleProvider), UserRole.parent);
    expect(container.read(currentAccountStatusProvider), AccountStatus.active);
  });
}
