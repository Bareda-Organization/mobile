import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/auth/presentation/signup_screen.dart';

class _Repository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<List<Never>>.value(const []);
}

/// F05-11 — API_SPEC §2.2 `login_id` 50자 이하 · `password` UTF-8 72바이트 이하.
/// 서버 422 문구를 기다리지 않고 입력란 옆에 이유를 보인다.
void main() {
  Future<void> pumpSignup(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_Repository())],
        child: const MaterialApp(home: SignupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('비밀번호가 72바이트를 넘으면 그 입력란 옆에 이유를 보인다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(1), '가' * 25);
    await tester.pump();

    expect(find.textContaining('72바이트'), findsOneWidget);
  });

  testWidgets('아이디가 50자를 넘으면 그 입력란 옆에 이유를 보인다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 51);
    await tester.pump();

    expect(find.textContaining('50자'), findsOneWidget);
  });

  testWidgets('한도 안의 입력에는 안내가 없다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 50);
    await tester.enterText(find.byType(TextField).at(1), '가' * 24);
    await tester.pump();

    expect(find.textContaining('72바이트'), findsNothing);
    expect(find.textContaining('50자'), findsNothing);
  });
}
