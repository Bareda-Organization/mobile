import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/data/selected_student_storage.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';

/// 로그아웃 호출만 받는 가짜 — 다른 메서드는 이 시험에서 불리면 안 된다.
class _StubAuthRepository implements AuthRepository {
  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 지우기가 코드 결함(`PlatformException` 이 아닌 예외)으로 실패하는 저장소.
class _FailingClearStorage extends SelectedStudentStorage {
  new();

  @override
  Future<void> clear() async => throw StateError('storage bug');
}

/// 연결을 닫았는지만 세는 실시간 클라이언트.
class _CountingWsClient extends BaraedaWebSocketClient {
  new()
    : super(
        url: 'ws://test.invalid/ws/location',
        tokenStorage: TokenStorage(
          accessTokenKey: 'sign-out-access',
          refreshTokenKey: 'sign-out-refresh',
        ),
      );

  int disconnectCalls = 0;

  @override
  void disconnect() => disconnectCalls++;
}

/// 선택 자녀 저장소를 지우다 실패해도 로그아웃은 끝까지 간다 — 실시간 연결을 닫고 역할을 비운다.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('저장소 지우기가 예외로 실패해도 연결을 닫고 역할을 비운다', (tester) async {
    final wsClient = _CountingWsClient();
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
          selectedStudentStorageProvider.overrideWithValue(
            _FailingClearStorage(),
          ),
          webSocketClientProvider.overrideWithValue(wsClient),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox)),
    );
    container.read(currentUserRoleProvider.notifier).state =
        UserRole.values.first;

    await expectLater(signOut(capturedRef), throwsStateError);

    expect(wsClient.disconnectCalls, 1);
    expect(container.read(currentUserRoleProvider), isNull);
  });
}
