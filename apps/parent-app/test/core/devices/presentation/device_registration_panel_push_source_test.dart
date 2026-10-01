import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';

/// NTF-12 · Ruling 510 — 설정 스위치가 푸시 토큰 공급자를 쓰고, 끈 기기를 기억한다.

/// 등록·해지 호출만 기록하고 나머지는 부르면 안 되는 가짜 저장소 계층.
class _RecordingAuthRepository implements AuthRepository {
  final List<String> registeredTokens = [];
  final List<String> unregisteredTokens = [];

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) async {
    registeredTokens.add(request.token);
    return DeviceRegistrationResponse(
      deviceId: request.deviceId,
      registeredAt: DateTime.utc(2026, 10),
    );
  }

  @override
  Future<void> unregisterDevice(String token) async =>
      unregisteredTokens.add(token);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _MemoryStorage extends DeviceRegistrationStorage {
  String? token;
  bool optedOut = false;

  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<bool> readOptedOut() async => optedOut;

  @override
  Future<void> saveOptedOut({required bool optedOut}) async =>
      this.optedOut = optedOut;
}

class _FixedTokenSource implements PushTokenSource {
  _FixedTokenSource(this.token);

  final String? token;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<void> get onMessage => const Stream.empty();
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required _RecordingAuthRepository repository,
  required _MemoryStorage storage,
  required PushTokenSource tokenSource,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        deviceRegistrationStorageProvider.overrideWithValue(storage),
        pushTokenSourceProvider.overrideWithValue(tokenSource),
      ],
      child: const MaterialApp(
        home: Scaffold(body: DeviceRegistrationPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('켜면 공급자의 토큰으로 등록하고 꺼 둔 기록을 지운다', (tester) async {
    final repository = _RecordingAuthRepository();
    final storage = _MemoryStorage()..optedOut = true;
    await _pumpPanel(
      tester,
      repository: repository,
      storage: storage,
      tokenSource: _FixedTokenSource('fcm-1'),
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(repository.registeredTokens, ['fcm-1']);
    expect(storage.optedOut, isFalse);
  });

  testWidgets('끄면 서버에 해지를 보내고 꺼 둔 것을 기억한다', (tester) async {
    final repository = _RecordingAuthRepository();
    final storage = _MemoryStorage()..token = 'fcm-1';
    await _pumpPanel(
      tester,
      repository: repository,
      storage: storage,
      tokenSource: _FixedTokenSource('fcm-1'),
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(repository.unregisteredTokens, ['fcm-1']);
    expect(storage.optedOut, isTrue);
  });

  testWidgets('공급자가 토큰을 못 주면 등록하지 않고 안내만 보인다', (tester) async {
    final repository = _RecordingAuthRepository();
    final storage = _MemoryStorage();
    await _pumpPanel(
      tester,
      repository: repository,
      storage: storage,
      tokenSource: _FixedTokenSource(null),
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(repository.registeredTokens, isEmpty);
    expect(find.text('이 기기에서는 아직 푸시 알림을 받을 수 없습니다'), findsOneWidget);
    expect(
      tester.widget<BaraedaSwitch>(find.byType(BaraedaSwitch)).checked,
      isFalse,
    );
  });
}
