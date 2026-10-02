import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// [BaraedaWebSocketClient] 를 상속해 실제 소켓을 열지 않고 3개 스트림만
/// 시험이 직접 흘려보낼 수 있게 만든 가짜 — `connect()` 를 no-op 으로
/// 덮어 네트워크 시도를 막는다. `frontend/packages/**`(`baraeda_core`)는
/// 읽기만 할 수 있어 그 클래스 자체는 고치지 않는다(COMMON.md §3) — 대신
/// 그 클래스가 이미 `final`이 아니고 각 멤버가 평범한 오버라이드 가능한
/// getter/메서드라, 상속만으로 시험용 대역을 만들 수 있다.
class _FakeWebSocketClient extends BaraedaWebSocketClient {
  new()
    : super(
        url: 'ws://test',
        tokenStorage: TokenStorage(
          accessTokenKey: 'test_access',
          refreshTokenKey: 'test_refresh',
        ),
      );

  final _connectionController = StreamController<WsConnectionState>.broadcast();
  final _forbiddenController = StreamController<String>.broadcast();
  final _sessionExpiredController = StreamController<void>.broadcast();

  bool disconnectCalled = false;

  @override
  Stream<WsConnectionState> get connectionState => _connectionController.stream;

  @override
  Stream<String> get forbiddenSubscriptions => _forbiddenController.stream;

  @override
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  @override
  void connect() {}

  @override
  void disconnect() {
    disconnectCalled = true;
  }

  void emitSessionExpired() => _sessionExpiredController.add(null);
}

/// [BaraedaWebSocketClient.sessionExpired] 를 [ManagerRunChannelController]
/// 가 구독해 REST 401 재발급 실패와 같은 경로(`account_session.dart` 의
/// `applyRoleAndStatus`)로 역할·상태를 비우는지 — 소켓 생명주기 전체가
/// 아니라 이 반응 하나만 격리해서 본다(`manager_run_channel_test.dart` 의
/// "순수 함수만 시험" 원칙과 같은 이유).
void main() {
  test('sessionExpired 한 번 → 역할·상태를 비운다(REST 로그인 만료와 같은 경로)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 컨트롤러 생성자가 요구하는 Ref 를 얻으려고 provider 콜백 안에서
    // 캡처한다 — WidgetRef 는 Ref 의 하위 타입이 아니라(sign_out_test.dart
    // 의 Consumer 방식을 여기서 그대로 쓸 수 없다) 위젯 없이 순수 Ref 가
    // 필요하다.
    late Ref capturedRef;
    final probe = Provider<void>((ref) => capturedRef = ref);
    container.read(probe);

    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    container.read(currentAccountStatusProvider.notifier).state =
        AccountStatus.active;

    final client = _FakeWebSocketClient();
    final controller = ManagerRunChannelController(
      capturedRef,
      'run-1',
      client: client,
    );
    addTearDown(controller.dispose);

    client.emitSessionExpired();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserRoleProvider), isNull);
    expect(container.read(currentAccountStatusProvider), isNull);
    expect(client.disconnectCalled, isTrue);
  });
}
