import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';

import '../../support/fake_academy_contact_store.dart';

/// 로그인 요청이 어떤 아이디·비밀번호로 나갔는지 기록하고 실패로 돌려보낸다.
class _RecordingLoginRepository implements AuthRepository {
  final calls = <List<String>>[];

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) {
    calls.add([loginId, password]);
    return Future.error(
      const Failure.api(
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: '아이디 또는 비밀번호가 올바르지 않습니다',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 로그인 요청마다 [failure] 로 거절한다.
class _RejectingLoginRepository implements AuthRepository {
  new(this.failure);

  final Failure failure;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => Future.error(failure);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  AuthRepository? repository,
  String? quickLoginPassword,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          authRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: quickLoginPassword == null
            ? const LoginScreen()
            : LoginScreen(quickLoginPassword: quickLoginPassword),
      ),
    ),
  );
  await tester.pump();
}

/// Ruling 329 · UF-X-04 — 매니저 앱(기사·동승자)은 학부모·학생과 같은
/// "학원 관계자 경유" 복구만 연다. 전화번호 복구 화면(SMS 연동 전 503)은
/// 만들지 않고, 로그인 화면에 안내 한 줄만 둔다(parent-app
/// `account_recovery_screen.dart` · 웹 `LoginForm.tsx` 와 같은 안내 방향).
void main() {
  testWidgets('로그인 화면에 학원 경유 비밀번호 초기화 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    expect(find.textContaining('학원'), findsWidgets);
    expect(find.textContaining('초기화'), findsOneWidget);
  });

  // Ruling 877 — 배포 시험 빌드에서만 역할별 빠른 로그인 단추가 나온다
  // (--dart-define=QUICK_LOGIN_PASSWORD).
  testWidgets('QL 값이 있으면 기사 · 동승자 단추가 보이고, 누르면 그 아이디로 로그인 요청이 나간다', (
    tester,
  ) async {
    final repository = _RecordingLoginRepository();
    await _pump(tester, repository: repository, quickLoginPassword: 'fake-pw');

    expect(find.text('기사 · driverA3'), findsOneWidget);
    expect(find.text('동승자 · escortA3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quick-login-driverA3')));
    await tester.pumpAndSettle();

    expect(repository.calls, [
      ['driverA3', 'fake-pw'],
    ]);
  });

  testWidgets('QL 값이 없으면 빠른 로그인 단추가 하나도 없다', (tester) async {
    await _pump(tester, quickLoginPassword: '');

    expect(find.byType(QuickLogin), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('driverA3'), findsNothing);
  });

  // Ruling 891 — 서버가 삭제된 매니저의 로그인을 비밀번호 대조 뒤 403 AUTH_STAFF_INACTIVE 로 거절한다.
  // 이유 모를 로그인 실패가 되지 않게 안내하고, 기기에 저장된 학원 번호가 전화번호 모양일 때만 전화 단추를 둔다(§12.7).
  group('삭제된 매니저 로그인 거절(AUTH_STAFF_INACTIVE)', () {
    const staffInactive = Failure.api(
      statusCode: 403,
      code: 'AUTH_STAFF_INACTIVE',
      message: '서버 문구',
    );
    const notice = '이 계정은 더 이상 쓸 수 없어요. 다니는 학원에 문의해 주세요';

    Future<({ProviderContainer container, List<Uri> opened})> submit(
      WidgetTester tester, {
      String? savedContact,
    }) async {
      final opened = <Uri>[];
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _RejectingLoginRepository(staffInactive),
            ),
            academyContactStoreProvider.overrideWithValue(
              FakeAcademyContactStore(savedContact),
            ),
            uriOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'driverA3');
      await tester.enterText(find.byType(TextField).at(1), 'pw-1234');
      await tester.tap(find.text('로그인'));
      await tester.pumpAndSettle();
      return (
        container: ProviderScope.containerOf(
          tester.element(find.byType(LoginScreen)),
        ),
        opened: opened,
      );
    }

    testWidgets('안내 문구가 뜨고 로그인은 만들어지지 않는다(서버 문구를 그대로 보이지 않는다)', (tester) async {
      final (:container, opened: _) = await submit(tester);

      expect(find.text(notice), findsOneWidget);
      expect(find.text('서버 문구'), findsNothing);
      expect(container.read(currentUserRoleProvider), isNull);
      expect(container.read(currentAccountStatusProvider), isNull);
    });

    testWidgets('저장된 학원 번호가 있으면 [학원에 전화 · 번호] 가 그 번호로 전화를 건다', (tester) async {
      final (container: _, :opened) = await submit(
        tester,
        savedContact: '032-000-1100',
      );

      await tester.tap(
        find.widgetWithText(BaraedaButton, '학원에 전화 · 032-000-1100'),
      );
      await tester.pumpAndSettle();

      expect(opened, [Uri(scheme: 'tel', path: '032-000-1100')]);
    });

    testWidgets('저장된 번호가 없으면 전화 단추 없이 안내 문구만 보인다', (tester) async {
      await submit(tester);

      expect(find.text(notice), findsOneWidget);
      expect(find.textContaining('학원에 전화'), findsNothing);
    });

    testWidgets('번호 모양이 아닌 저장값이면 전화 단추를 그리지 않는다', (tester) async {
      await submit(tester, savedContact: '평일 오전 9시부터 6시까지');

      expect(find.text(notice), findsOneWidget);
      expect(find.textContaining('학원에 전화'), findsNothing);
    });
  });
}
