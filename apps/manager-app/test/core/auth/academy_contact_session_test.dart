import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';

import '../../support/fake_token_storage.dart';

const _academy = AcademyRef(id: '1', name: '바래다학원 A', contact: '02-1234-5678');

class _Auth implements AuthRepository {
  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async => const LoginResponse(
    accessToken: 'a',
    role: AccountRole.escort,
    status: AccountStatus.active,
    accountId: '1',
    academy: _academy,
  );

  @override
  Future<MeResponse> me() async => const MeResponse(
    accountId: '1',
    loginId: 'escortA1',
    name: '동승자',
    phone: '010-0000-0000',
    role: AccountRole.escort,
    status: AccountStatus.active,
    academy: _academy,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 통신 두절 때 학원에 전화하려면 앱이 학원 연락처를 알고 있어야 한다 — 로그인 응답과 자동 로그인(`/me`) 두 경로가 채운다(R46).
void main() {
  testWidgets('로그인에 성공하면 응답의 학원 연락처를 들고 있는다', (tester) async {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'escortA1');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('로그인하기'));
    await tester.pumpAndSettle();

    expect(container.read(academyContactProvider), '02-1234-5678');
  });

  test('앱을 다시 켜 자동 로그인하면 /me 의 학원 연락처를 들고 있는다', () async {
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(
          FakeTokenStorage(seedRefreshToken: 'refresh'),
        ),
        authRepositoryProvider.overrideWithValue(_Auth()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authBootstrapProvider.future);

    expect(container.read(academyContactProvider), '02-1234-5678');
  });
}
