import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/auth/presentation/blocked_screen.dart';

/// R32 P13 — 차단 안내가 "학원 관리자(메인 관리자)" 처럼 두 역할을 섞어, 사용자가 누구에게
/// 물어야 하는지 알 수 없었다. 문의처는 학원 하나로 적는다(UF-X-04 · Ruling 329).
void main() {
  testWidgets('차단 안내의 문의처는 학원 하나이고 관리자 역할 이름을 섞지 않는다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BlockedScreen()));

    expect(find.textContaining('학원에 문의해 주세요'), findsOneWidget);
    expect(find.textContaining('메인 관리자'), findsNothing);
    expect(find.textContaining('학원 관리자'), findsNothing);
  });
}
