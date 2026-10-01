import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/auth/presentation/account_recovery_screen.dart';

/// P2 게이트 조건 ① — 계정 열거(enumeration) 노출 확인. 서버는 번호의 가입 여부를
/// 응답으로 구분하지 않는다(Ruling 553) — 인증번호 요청이 성공한 뒤 안내가 "보냈다" 고
/// 단정하면 미등록 번호에서는 사실이 아니고, 실패 문구가 코드별로 갈리면 단서가 된다.
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

/// FE-R2 목표 10 — 제출 중 표시. `recover()` 가 끝나는 시점을 이
/// `Completer` 로 직접 쥐고 있어야 "제출 중" 인 프레임을 관측할 수 있다
/// (`pumpAndSettle` 로는 그 순간을 지나쳐 버린다). password_change_screen
/// 과 달리 이 화면은 실패 시에도 `_submitting` 을 내리므로(§ 클래스의
/// `_requestCode` 참고) 실패로 끝내도 "사라진다" 를 그대로 관측할 수 있다.
class _StallingAuthRepository implements AuthRepository {
  final recoverCalled = Completer<void>();
  final _recoverResult = Completer<void>();

  void failRecover() => _recoverResult.completeError(const Failure.network());

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
  }) async {
    recoverCalled.complete();
    await _recoverResult.future;
  }

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

/// 인증번호 요청이 성공하는 가짜 — 서버가 미등록 번호에도 200 을 주는 경우와 같은 화면 경로를 만든다.
class _OkAuthRepository extends _FailingAuthRepository {
  _OkAuthRepository() : super('');

  @override
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) async {}
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
  testWidgets('인증번호 요청이 성공하면 가입 여부를 단정하지 않는 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_OkAuthRepository()),
        ],
        child: const MaterialApp(home: AccountRecoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '01000000000');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('가입된 번호라면'), findsOneWidget);
    expect(find.text('인증번호를 발송했습니다. 문자로 받은 번호를 입력해 주세요'), findsNothing);
  });

  testWidgets('VERIFICATION_CODE_INVALID 는 이유를 가르지 않는 공용 문구를 보여준다', (
    tester,
  ) async {
    await _pumpAndRequestCode(tester, 'VERIFICATION_CODE_INVALID');

    expect(find.text(_expectedSharedMessage), findsOneWidget);
    // 서버 원본 메시지가 그대로 새면 안 된다 — 코드로 구분되는 순간 열거 공격에 쓰인다.
    expect(find.text('서버 원본 메시지(VERIFICATION_CODE_INVALID)'), findsNothing);
  });

  // Ruling 329 — SMS 연동 전까지 서버가 503 RECOVERY_UNAVAILABLE 을 낸다. 원문 메시지나 일반 오류가
  // 아니라 "학원에 요청" 이라는 다음 행동을 알려야 복구가 막힌 채 끝나지 않는다.
  testWidgets('RECOVERY_UNAVAILABLE 은 학원에 초기화를 요청하라고 안내한다', (tester) async {
    await _pumpAndRequestCode(tester, 'RECOVERY_UNAVAILABLE');

    expect(find.textContaining('학원에 비밀번호 초기화를 요청'), findsWidgets);
    expect(find.text('서버 원본 메시지(RECOVERY_UNAVAILABLE)'), findsNothing);
  });

  testWidgets('요청 전에도 관리자 경유 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserRoleProvider.overrideWith((ref) => null)],
        child: const MaterialApp(home: AccountRecoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('학원에 비밀번호 초기화를 요청'), findsOneWidget);
  });

  // 이 화면은 비로그인 진입점이다(클래스 문서 참고) — `router.dart` 의
  // `onAuthScreen` 판정이 로그인 전에도 이 경로를 허용하는 것은 코드로
  // 확인됐지만, 그 판정을 통과했을 때 화면 자체가 실제로 뜨는지는 위 두
  // 시험 모두 확인하지 않는다(둘 다 에러 문구만 본다). 여기서는
  // `currentUserRoleProvider` 를 명시적으로 `null`(비로그인)로 두고
  // 화면의 핵심 요소(제목·입력 폼·버튼)가 실제로 그려지는지를 본다.
  testWidgets('비로그인 상태로 진입해도 화면이 렌더된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserRoleProvider.overrideWith((ref) => null)],
        child: const MaterialApp(home: AccountRecoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아이디·비밀번호 찾기'), findsOneWidget);
    // 라벨은 필수 표시(`*`)가 별도 TextSpan 으로 붙는 RichText 라
    // (`input.dart` 의 `_InputLabel`) 렌더 문자열이 아니라 위젯 속성으로
    // 확인한다.
    expect(
      find.byWidgetPredicate(
        (w) => w is BaraedaInput && w.label == '가입 시 등록한 휴대폰 번호',
      ),
      findsOneWidget,
    );
    expect(find.text('인증번호 받기'), findsOneWidget);
  });

  // FE-R2 목표 10 — password_change_screen.dart 와 동일한 표시(버튼
  // 비활성화 + `CircularProgressIndicator`)를 이 화면에도 확인한다.
  testWidgets('제출 중에는 진행 표시기가 뜨고, 끝나면 사라진다', (tester) async {
    final repository = _StallingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AccountRecoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField).first, '01000000000');
    await tester.tap(find.text('인증번호 받기'));
    // API 호출이 나갔지만 아직 응답이 오지 않은 시점까지만 프레임을 민다.
    await tester.pump();
    await repository.recoverCalled.future;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.failRecover();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
