import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/settings/presentation/password_change_screen.dart';

/// P2 게이트 조건 ① — `password_change_screen.dart:33`(정확한 줄은 그
/// 사이 다른 편집으로 이동했으나 대상은 `_submit()` 첫머리의
/// `isEmpty` 빈 입력 가드) 를 없애면 빈 문자열로도
/// `AuthRepository.changePassword` 가 호출된다. 이 테스트는 입력을 전혀
/// 하지 않고 제출 버튼만 눌러 그 호출이 실제로 막히는지 본다.
class _CountingAuthRepository implements AuthRepository {
  int changePasswordCallCount = 0;

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
  }) async {
    changePasswordCallCount++;
  }

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

/// FE-R2 목표 10 — 제출 중 표시. `changePassword` 가 끝나는 시점을 이
/// `Completer` 로 직접 쥐고 있어야 "제출 중" 인 프레임을 관측할 수 있다
/// (`pumpAndSettle` 로는 그 순간을 지나쳐 버린다).
class _StallingAuthRepository implements AuthRepository {
  final changePasswordCalled = Completer<void>();
  final _changePasswordResult = Completer<void>();

  // 실패로 끝낸다 — 성공 경로는 `_submitting` 을 다시 내리지 않고 router
  // 리다이렉트로 화면을 통째로 치워 버리므로(클래스 문서 참고), 이 화면
  // 하나만 올린 시험에서는 "표시기가 사라진다" 를 관측할 방법이 없다.
  void failChangePassword() =>
      _changePasswordResult.completeError(const Failure.network());

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

  // 화면은 changePassword 성공 뒤 곧바로 logout() 을 부른다(클래스 문서
  // 참고, 실패해도 무시한다) — 여기서 던지면 이 시험의 관심사(로딩 표시)와
  // 무관한 예외로 실패하므로 성공으로 둔다.
  @override
  Future<void> logout() async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalled.complete();
    await _changePasswordResult.future;
  }

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

void main() {
  testWidgets('두 입력란이 비어 있으면 제출을 눌러도 changePassword 를 호출하지 않는다', (
    tester,
  ) async {
    final repository = _CountingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(
      repository.changePasswordCallCount,
      0,
      reason: '빈 입력값으로는 API 호출 자체가 나가면 안 된다',
    );
  });

  // FE-R2 목표 10 — 버튼 비활성화뿐 아니라 로딩 표시기도 함께 뜨는지 본다.
  // `changePassword` 응답이 오기 전 프레임을 `pump()` 로 붙잡아 확인한다.
  testWidgets('제출 중에는 진행 표시기가 뜨고, 끝나면 사라진다', (tester) async {
    final repository = _StallingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'current-pw');
    await tester.enterText(find.byType(TextField).at(1), 'new-pw');
    await tester.tap(find.text('변경하기'));
    // API 호출이 나갔지만 아직 응답이 오지 않은 시점까지만 프레임을 민다.
    await tester.pump();
    await repository.changePasswordCalled.future;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.failChangePassword();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
