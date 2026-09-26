import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';

/// M5(Ruling 329 · UF-X-04) — 매니저 앱(기사·동승자)은 학부모·학생과 같은
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
}
