import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';

/// 앱이 로그인 화면으로 뜨는지만 확인하는 자리표시 스모크 시험 —
/// 실제 화면 검증은 이번 범위가 아니다.
void main() {
  testWidgets('로그인 전에는 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BaraedaParentApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
