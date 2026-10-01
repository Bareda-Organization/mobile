import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';

/// P2 게이트 조건 ① — `device_registration_panel.dart:89` 에 `on Failure
/// catch` 블록 안에서 `_registered = value;` 를 끼워 넣으면, 서버 등록이
/// 실패해도 스위치가 "켜졌다" 로 표시된다(실패가 성공으로 둔갑). 이
/// 테스트는 실패 후 스위치가 실패 전 상태(꺼짐)를 유지하는지 직접 본다.
class _ThrowingAuthRepository implements AuthRepository {
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
  }) => throw UnimplementedError();

  @override
  Future<MeResponse> me() => throw UnimplementedError();

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => Future.error(
    const Failure.api(
      statusCode: 500,
      code: 'DEVICE_REGISTER_FAILED',
      message: '기기 등록 상태를 바꾸지 못했습니다',
    ),
  );

  @override
  Future<void> unregisterDevice(String token) => throw UnimplementedError();
}

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

void main() {
  testWidgets('등록이 실패하면 스위치는 켜진 것으로 표시되지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_ThrowingAuthRepository()),
          deviceRegistrationStorageProvider.overrideWithValue(
            _FakeDeviceRegistrationStorage(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DeviceRegistrationPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var deviceSwitch = tester.widget<BaraedaSwitch>(
      find.byType(BaraedaSwitch),
    );
    expect(deviceSwitch.checked, isFalse);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    deviceSwitch = tester.widget<BaraedaSwitch>(find.byType(BaraedaSwitch));
    expect(
      deviceSwitch.checked,
      isFalse,
      reason: '서버 등록이 실패했으면 스위치가 켜진 것으로 표시되면 안 된다',
    );
    expect(find.text('기기 등록 상태를 바꾸지 못했습니다'), findsOneWidget);
  });
}
