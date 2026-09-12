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
}
