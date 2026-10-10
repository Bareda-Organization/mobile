import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/blocked_screen.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';

import '../../support/fake_academy_contact_store.dart';

/// M-M7(AUTH-06 · C-11) — 로그인 차단은 **메인 관리자만** 푼다. 학원 관리자(관계자)는 풀 수 없으므로 화면 문구가
/// 학원 관리자를 해제 주체로 말하지 않는다. 문의처가 학원이라는 안내(전화·문의)는 그대로다.
class _WrongPasswordRepository implements AuthRepository {
  const new({this.remaining = 2});

  /// 서버가 알려 주는 남은 시도 횟수(`details.remaining_attempts`).
  final int remaining;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async =>
      // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
      // ignore: only_throw_errors
      throw ApiFailure(
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: '아이디 또는 비밀번호가 올바르지 않습니다',
        details: {'remaining_attempts': remaining},
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> failLogin(WidgetTester tester, int remaining) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _WrongPasswordRepository(remaining: remaining),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'driverA1');
    await tester.enterText(fields.at(1), 'wrong');
    await tester.tap(find.widgetWithText(BaraedaButton, '로그인'));
    await tester.pumpAndSettle();
  }

  // B2 — 잠금 경고는 잔여 2회 이하부터 보인다(학부모 앱과 같다).
  testWidgets('잔여 시도 3회면 잠금 경고가 없고, 2회 · 1회면 있다', (tester) async {
    await failLogin(tester, 3);
    expect(find.textContaining('번 더 틀리면 계정이 잠겨요'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await failLogin(tester, 2);
    expect(find.text('2번 더 틀리면 계정이 잠겨요'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await failLogin(tester, 1);
    expect(find.text('1번 더 틀리면 계정이 잠겨요'), findsOneWidget);
  });

  testWidgets('로그인 한도 경고는 메인 관리자가 풀어 준다고 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            const _WrongPasswordRepository(),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'driverA1');
    await tester.enterText(fields.at(1), 'wrong');
    await tester.tap(find.widgetWithText(BaraedaButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.text('2번 더 틀리면 계정이 잠겨요'), findsOneWidget);
    expect(find.textContaining('메인 관리자가 풀어 줄 때까지'), findsOneWidget);
    expect(find.textContaining('학원 관리자'), findsNothing);
  });

  testWidgets('차단 화면은 잠금을 메인 관리자만 풀 수 있다고 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore('032-000-1100'),
          ),
        ],
        child: const MaterialApp(home: BlockedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('잠금은 메인 관리자만 풀 수 있어요'), findsOneWidget);
    expect(find.textContaining('학원 관리자'), findsNothing);
    // 문의처는 학원 — 전화 단추는 그대로.
    expect(find.text('학원에 전화 · 032-000-1100'), findsOneWidget);
  });
}
