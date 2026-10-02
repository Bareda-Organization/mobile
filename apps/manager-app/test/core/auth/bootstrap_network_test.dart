import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';

import '../../support/fake_token_storage.dart';

/// `/me` 만 쓰는 가짜 — 첫 호출은 [failure] 로 실패하고 그 뒤로는 동승자 계정을 돌려준다.
class _MeRepository implements AuthRepository {
  _MeRepository(this.failure);

  final Failure failure;
  int calls = 0;

  @override
  Future<MeResponse> me() async {
    calls++;
    if (calls == 1) return await Future<MeResponse>.error(failure);
    return const MeResponse(
      accountId: 'a-1',
      loginId: 'escortA1',
      name: '동승자',
      phone: '010',
      role: AccountRole.escort,
      status: AccountStatus.active,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// F06-10 — 저장된 로그인이 있는데 시작할 때 연결이 잠깐 끊겨 있으면 로그인 화면이 아니라 다시 시도
/// 화면이어야 한다(토큰은 그대로다). 인증 자체가 거절된 경우만 로그인 화면으로 간다.
void main() {
  Future<_MeRepository> pumpApp(WidgetTester tester, Failure failure) async {
    final repository = _MeRepository(failure);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(
            FakeTokenStorage(seedRefreshToken: 'refresh'),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          // 다시 시도가 성공하면 홈이 열린다 — 홈이 부르는 요청은 가짜로 막는다.
          todayRunsProvider.overrideWith((ref) async => []),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('시작할 때 네트워크 오류면 로그인 화면 대신 다시 시도 안내를 보인다', (tester) async {
    await pumpApp(tester, const Failure.network());

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('서버 오류(5xx)여도 다시 시도 안내를 보인다', (tester) async {
    await pumpApp(
      tester,
      const Failure.api(statusCode: 503, code: 'X', message: 'down'),
    );

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('[다시 시도] 로 /me 를 다시 불러 로그인 상태로 들어간다', (tester) async {
    final repository = await pumpApp(tester, const Failure.network());

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    // 홈의 30초 갱신 타이머를 정리한다.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('인증 자체가 거절된 것(401)이면 지금처럼 로그인 화면으로 간다', (tester) async {
    await pumpApp(
      tester,
      const Failure.api(statusCode: 401, code: 'AUTH', message: '만료'),
    );

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
