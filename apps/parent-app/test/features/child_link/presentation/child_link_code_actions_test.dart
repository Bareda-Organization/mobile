import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';
import 'package:parent_app/features/child_link/domain/link_repository.dart';
import 'package:parent_app/features/child_link/presentation/child_link_screen.dart';

/// R46 B2 #21 — 학생이 만든 6자리 코드를 손으로 옮겨 적지 않고 복사해 보내고, 만료까지 남은 시간을 본다.
/// 사양 판단(학생 계정이 없는 어린 자녀는 연결이 막힌다 — Ruling 324)은 바꾸지 않는다.
class _Link implements LinkRepository {
  new(this.expiresAt);

  final DateTime expiresAt;

  @override
  Future<LinkCodeResult> generateLinkCode() async =>
      LinkCodeResult(code: '482913', expiresAt: expiresAt);

  @override
  Future<LinkConfirmResult> confirmLink(String code) =>
      throw UnimplementedError();
}

class _MutableClock implements Clock {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

Future<void> _pumpCode(
  WidgetTester tester, {
  required DateTime expiresAt,
  required Clock clock,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkRepositoryProvider.overrideWithValue(_Link(expiresAt)),
        currentUserRoleProvider.overrideWith((ref) => UserRole.student),
        clockProvider.overrideWithValue(clock),
      ],
      child: const MaterialApp(home: ChildLinkScreen()),
    ),
  );
  await tester.tap(find.text('코드 만들기'));
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime(2026, 9, 12, 7);
  final expiresAt = DateTime(2026, 9, 12, 7, 10);

  testWidgets('만료까지 남은 시간을 분 단위로 보이고 1분마다 줄어든다', (tester) async {
    final clock = _MutableClock(now);
    await _pumpCode(tester, expiresAt: expiresAt, clock: clock);
    expect(find.textContaining('남은 시간 10분'), findsOneWidget);

    clock.value = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(find.textContaining('남은 시간 9분'), findsOneWidget);
  });

  testWidgets('만료되면 코드를 못 쓴다고 알리고 복사 단추를 끄고 새 코드를 주 행동으로 둔다', (tester) async {
    final clock = _MutableClock(now);
    await _pumpCode(tester, expiresAt: expiresAt, clock: clock);
    // 살아 있는 동안은 안내 문구 복사가 주 행동이고 만료 띠는 없다.
    expect(find.text('코드가 만료됐어요'), findsNothing);
    expect(
      tester
          .widget<BaraedaCodeDisplay>(find.byType(BaraedaCodeDisplay))
          .expired,
      isFalse,
    );

    clock.value = expiresAt;
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('코드가 만료됐어요'), findsOneWidget);
    expect(find.textContaining('지금은 쓸 수 없어요'), findsOneWidget);
    expect(
      tester
          .widget<BaraedaCodeDisplay>(find.byType(BaraedaCodeDisplay))
          .expired,
      isTrue,
    );
    for (final label in ['코드만 복사', '안내 문구 복사']) {
      expect(
        tester
            .widget<BaraedaButton>(find.widgetWithText(BaraedaButton, label))
            .onPressed,
        isNull,
        reason: label,
      );
    }
    expect(find.text('새 코드 만들기'), findsOneWidget);
  });

  group('복사', () {
    String? copied;

    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('[코드만 복사] 는 6자리 코드만 복사한다', (tester) async {
      await _pumpCode(tester, expiresAt: expiresAt, clock: _MutableClock(now));

      await tester.tap(find.text('코드만 복사'));
      await tester.pump();

      expect(copied, '482913');
      expect(find.text('코드를 복사했어요'), findsOneWidget);
    });

    testWidgets('[안내 문구 복사] 는 어디에 입력하는지와 남은 시간을 함께 복사한다', (tester) async {
      await _pumpCode(tester, expiresAt: expiresAt, clock: _MutableClock(now));

      await tester.tap(find.text('안내 문구 복사'));
      await tester.pump();

      expect(copied, contains('482913'));
      // 학부모 앱의 진입점은 설정 탭의 [자녀 추가] 다 — 없는 [자녀 연결] 메뉴를 가리키면 안 된다.
      expect(copied, contains('[설정] › [자녀 추가]'));
      expect(copied, isNot(contains('[자녀 연결]')));
      expect(copied, contains('7:10'));
      expect(find.text('안내 문구를 복사했어요'), findsOneWidget);
    });
  });
}
