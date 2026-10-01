import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/delay/presentation/delay_screen.dart';

import '../../support/line_breaks.dart';

/// 지연 알림 화면의 문구 미리보기는 여러 줄이 되는 문단이다 — 낱말 한가운데서 줄이 바뀌면 안 된다
/// (R46-POLISH Ruling 594, R46-SCREEN 에서 `사 / 유와` 로 끊겼다).
void main() {
  testWidgets('문구 미리보기는 낱말 경계에서만 줄이 바뀐다 (375pt · 글자 1.3배)', (tester) async {
    useNarrowLargeText(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.escort),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const DelayScreen(),
        ),
      ),
    );

    final paragraph = paragraphContaining(tester, '이 들어갑니다');
    expect(
      layoutLike(paragraph).computeLineMetrics().length,
      greaterThan(1),
      reason: '줄이 바뀌어야 이 시험이 무언가를 검사한다',
    );
    expect(midWordLineBreaks(paragraph), isEmpty);
  });
}
