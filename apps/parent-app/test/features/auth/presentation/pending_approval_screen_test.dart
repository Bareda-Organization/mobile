import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/devices/data/device_registration_storage.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';

/// Ruling 267(P2 게이트 조건 ②) — `pending` 계정 화면에 심은 단말 등록
/// 패널이 실제로 나타나는지(도달성)와 토글이 실제 등록 호출까지 이어지는지
/// (동작)를 함께 확인한다. 도달성만 보면 "빈 패널이 떠 있을 뿐" 인
/// 사고를 못 잡고, 동작만 보면 "이 화면에서는 애초에 안 보인다" 는
/// 사고를 못 잡는다 — 그래서 두 가지를 각각 별도 테스트로 확인한다.
class _StubAuthRepository implements AuthRepository {
  DeviceRegistrationRequest? registeredWith;
  String? unregisteredToken;
  int logoutCallCount = 0;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [];

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      throw UnimplementedError();

  @override
  Future<SignupStatusResponse> signupStatus() async => SignupStatusResponse(
    status: AccountStatus.pending,
    academyName: '바래다학원',
    academyRegion: '서울',
    academyCode: 'A-001',
    requestedAt: DateTime(2026, 9),
    academyContact: '02-000-0000',
  );

  @override
  Future<ReapplyResponse> reapply({required String academyId}) =>
      throw UnimplementedError();

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }

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
  ) async {
    registeredWith = request;
    return DeviceRegistrationResponse(
      deviceId: request.deviceId,
      registeredAt: DateTime(2026, 9, 12),
    );
  }

  @override
  Future<void> unregisterDevice(String token) async {
    unregisteredToken = token;
  }
}

/// `DeviceRegistrationStorage` 는 내부에 `FlutterSecureStorage` 를 들고
/// 있어 시험 환경의 플랫폼 채널을 못 탄다(`fake_token_storage.dart` 와
/// 같은 사정) — 메모리로만 도는 대역으로 바꾼다.
class _FakeDeviceRegistrationStorage extends DeviceRegistrationStorage {
  String? _deviceId;
  String? _token;

  @override
  Future<String> readOrCreateDeviceId() async => _deviceId ??= 'device-1';

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}

Future<void> _pumpPendingApproval(
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
      ],
      child: const MaterialApp(home: PendingApprovalScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('가입 승인 대기 화면에 단말 등록 패널이 도달 가능하다', (tester) async {
    await _pumpPendingApproval(tester, _StubAuthRepository());

    expect(find.byType(DeviceRegistrationPanel), findsOneWidget);
  });

  testWidgets('대기 화면의 단말 등록 패널에서 토글하면 registerDevice 가 실제로 호출된다', (
    tester,
  ) async {
    final authRepository = _StubAuthRepository();
    await _pumpPendingApproval(tester, authRepository);

    expect(authRepository.registeredWith, isNull);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(authRepository.registeredWith, isNotNull);
    expect(authRepository.registeredWith!.platform, isNotEmpty);
  });

  // F2 — `settings_screen.dart` 의 확인 대화를 그대로 재사용하는지 검사한다.
  // 지금 코드는 확인 대화 없이 바로 logout() 을 부른다 — 버튼 라벨
  // '로그아웃하기' 가 대화의 확정 버튼 라벨과 같아 `find.widgetWithText`
  // 로 `TextButton`(대화 쪽)만 짚어 원래 화면 버튼과 가른다.
  group('F2 — 로그아웃 확인 대화(P 의 확인 대화 재사용)', () {
    // 로그아웃 버튼은 스크롤 목록 맨 아래라 기본 시험 화면(800x600) 밖에
    // 있다 — `ensureVisible` 로 먼저 스크롤한다.
    Future<void> tapLogoutButton(WidgetTester tester) async {
      final button = find.text('로그아웃하기');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
    }

    testWidgets('로그아웃하기 버튼을 누르면 확인 대화가 뜨고, 아직 요청을 보내지 않는다', (
      tester,
    ) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(authRepository.logoutCallCount, 0);
    });

    testWidgets('확인 대화에서 취소하면 요청을 보내지 않는다', (tester) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(authRepository.logoutCallCount, 0);
    });

    testWidgets('확인 대화에서 확정하면 요청이 실행된다', (tester) async {
      final authRepository = _StubAuthRepository();
      await _pumpPendingApproval(tester, authRepository);

      await tapLogoutButton(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '로그아웃하기'));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCallCount, 1);
    });
  });
}
