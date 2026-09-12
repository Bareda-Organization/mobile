import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/auth/presentation/account_recovery_screen.dart';

/// P2 게이트 조건 ① — 계정 열거(enumeration) 노출 확인. `_messageFor` 가
/// `ACCOUNT_NOT_FOUND`(미등록 번호) 와 `VERIFICATION_CODE_INVALID`(등록된
/// 번호인데 인증번호가 틀림) 를 서로 다른 문구로 보여주면, 공격자가 문구
/// 차이만으로 "이 번호가 가입돼 있는지" 를 알아낼 수 있다. 두 코드가
/// **정확히 같은 문구**를 내는지를 이 테스트가 직접 대조한다 — 지금까지는
/// 클래스 문서의 주석 하나만 이 사실을 지키고 있었고 테스트는 없었다.
class _FailingAuthRepository implements AuthRepository {
  _FailingAuthRepository(this._code);

  final String _code;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [];

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
  Future<void> logout() => throw UnimplementedError();

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
  }) => Future.error(
    Failure.api(statusCode: 404, code: _code, message: '서버 원본 메시지($_code)'),
  );

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

const _expectedSharedMessage = '휴대폰 번호 또는 인증번호를 확인할 수 없습니다';

Future<void> _pumpAndRequestCode(
  WidgetTester tester,
  String failureCode,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          _FailingAuthRepository(failureCode),
        ),
      ],
      child: const MaterialApp(home: AccountRecoveryScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, '01000000000');
  await tester.tap(find.text('인증번호 받기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ACCOUNT_NOT_FOUND 은 계정 존재 여부를 드러내지 않는 공용 문구를 보여준다', (
    tester,
  ) async {
    await _pumpAndRequestCode(tester, 'ACCOUNT_NOT_FOUND');

    expect(find.text(_expectedSharedMessage), findsOneWidget);
    // 서버 원본 메시지가 그대로 새면 안 된다 — 코드로 구분되는 순간
    // 열거 공격에 쓰인다.
    expect(find.text('서버 원본 메시지(ACCOUNT_NOT_FOUND)'), findsNothing);
  });

  testWidgets('VERIFICATION_CODE_INVALID 도 ACCOUNT_NOT_FOUND 와 같은 문구를 보여준다', (
    tester,
  ) async {
    await _pumpAndRequestCode(tester, 'VERIFICATION_CODE_INVALID');

    expect(
      find.text(_expectedSharedMessage),
      findsOneWidget,
      reason: '두 실패 코드가 다른 문구로 갈리면 계정 존재 여부가 노출된다',
    );
  });
}
