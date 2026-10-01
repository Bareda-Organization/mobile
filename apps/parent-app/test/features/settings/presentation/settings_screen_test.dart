import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';

/// LO — `active` 사용자가 닿는 로그아웃 진입점(설정 화면)에 확인 대화 1회를
/// 끼워 넣는지, 그리고 요청이 실패해도 로그인 화면으로 넘어갈 조건(역할·
/// 상태 provider 를 비움 — `router.dart` 가 이 값을 보고 리다이렉트한다)을
/// 만족하는지 검사한다.
///
/// **진입점 자체는 이미 있다**(`a27f15eb`, 2026-09-23) — 이 파일은 "탭
/// 즉시 로그아웃" 이던 지금 동작에 확인 대화를 끼워 넣는 변경만 잡는다
/// (보고서 §2 — BRIEF 의 "진입점 부재" 전제와 실측이 어긋난 지점).
class _StubAuthRepository implements AuthRepository {
  _StubAuthRepository({this.logoutFailure});

  final Failure? logoutFailure;
  int logoutCallCount = 0;

  @override
  Future<void> logout() async {
    logoutCallCount++;
    final failure = logoutFailure;
    if (failure != null) return Future.error(failure);
  }

  // 이 화면이 실제로 부르지 않는 메서드는 미구현으로 둔다 — 범위 밖
  // 호출이 생기면 시험이 바로 죽어서 드러난다.
  @override
  Future<List<AcademySummary>> searchAcademies(String query) =>
      throw UnimplementedError();

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      throw UnimplementedError();

  @override
  Future<SignupStatusResponse> signupStatus() => throw UnimplementedError();

  @override
  Future<ReapplyResponse> reapply({required String academyId}) =>
      throw UnimplementedError();

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) => throw UnimplementedError();

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

/// `DeviceRegistrationStorage` 는 내부에 `FlutterSecureStorage` 를 들고
/// 있어 시험 환경의 플랫폼 채널을 못 탄다 — 메모리 대역으로 바꾼다
/// (`pending_approval_screen_test.dart` 와 같은 사정).
class _FakeDeviceRegistrationStorage extends DeviceRegistrationStorage {
  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AuthRepository authRepository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        deviceRegistrationStorageProvider.overrideWithValue(
          _FakeDeviceRegistrationStorage(),
        ),
        notificationSettingsProvider.overrideWith(
          (ref) async => const NotificationSettings(
            arrive: true,
            boarding: true,
            noShow: true,
          ),
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
        currentAccountStatusProvider.overrideWith(
          (ref) => AccountStatus.active,
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('로그아웃 버튼을 누르면 확인 대화가 뜨고, 아직 로그아웃 요청을 보내지 않는다', (
    tester,
  ) async {
    final repository = _StubAuthRepository();
    await _pumpSettings(tester, repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.byType(BaraedaDialog), findsOneWidget);
    expect(repository.logoutCallCount, 0);
  });

  testWidgets('확인 대화에서 취소하면 로그아웃 요청을 보내지 않는다', (tester) async {
    final repository = _StubAuthRepository();
    await _pumpSettings(tester, repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.byType(BaraedaDialog), findsNothing);
    expect(repository.logoutCallCount, 0);
  });

  testWidgets(
    '확인 대화에서 로그아웃을 확정하면 요청이 실행되고 역할·상태가 비워진다',
    (tester) async {
      final repository = _StubAuthRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          deviceRegistrationStorageProvider.overrideWithValue(
            _FakeDeviceRegistrationStorage(),
          ),
          notificationSettingsProvider.overrideWith(
            (ref) async => const NotificationSettings(
              arrive: true,
              boarding: true,
              noShow: true,
            ),
          ),
          currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그아웃하기'));
      await tester.pumpAndSettle();

      expect(repository.logoutCallCount, 1);
      expect(container.read(currentUserRoleProvider), isNull);
      expect(container.read(currentAccountStatusProvider), isNull);
    },
  );

  testWidgets(
    '로그아웃 요청이 실패해도 역할·상태는 비워진다(로그인 화면으로 넘어갈 조건)',
    (tester) async {
      final repository = _StubAuthRepository(
        logoutFailure: const Failure.network(),
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          deviceRegistrationStorageProvider.overrideWithValue(
            _FakeDeviceRegistrationStorage(),
          ),
          notificationSettingsProvider.overrideWith(
            (ref) async => const NotificationSettings(
              arrive: true,
              boarding: true,
              noShow: true,
            ),
          ),
          currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그아웃하기'));
      await tester.pumpAndSettle();

      expect(repository.logoutCallCount, 1);
      expect(container.read(currentUserRoleProvider), isNull);
      expect(container.read(currentAccountStatusProvider), isNull);
    },
  );
}
