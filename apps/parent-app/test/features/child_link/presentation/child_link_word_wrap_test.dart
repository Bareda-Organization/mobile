import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/child_link/presentation/child_link_screen.dart';

import '../../../support/line_breaks.dart';

/// 학생의 연결 코드 설명은 여러 줄 문단이다 — 낱말 한가운데서 줄이 바뀌면 안 된다
/// (R46-POLISH Ruling 594, R46-SCREEN 에서 `없습니 / 다.` 로 끊겼다).
void main() {
  testWidgets('연결 코드 설명은 낱말 경계에서만 줄이 바뀐다 (375pt · 글자 1.3배)', (tester) async {
    useNarrowLargeText(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.student),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ChildLinkScreen(),
        ),
      ),
    );

    final paragraph = paragraphContaining(tester, '일정 시간이 지나면 만료됩니다');
    expect(
      layoutLike(paragraph).computeLineMetrics().length,
      greaterThan(1),
      reason: '줄이 바뀌어야 이 시험이 무언가를 검사한다',
    );
    expect(midWordLineBreaks(paragraph), isEmpty);
  });
}
