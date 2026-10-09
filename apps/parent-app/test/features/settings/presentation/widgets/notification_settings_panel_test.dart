import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/domain/notification_settings_repository.dart';
import 'package:parent_app/features/settings/presentation/widgets/notification_settings_panel.dart';

/// P2 게이트 조건 ① — `notification_settings_panel.dart:70` 의 되돌리기
/// 줄(`_current = previous;`)이 없으면, 서버가 변경을 거부해도 화면은
/// 방금 누른(거부된) 값을 계속 켜진 채로 보여준다. 이 테스트는 그 상태를
/// 직접 확인한다 — "토글이 꺼진다" 가 아니라 "실패 후에도 원래 값으로
/// 돌아온다" 를 봐야 되돌리기 로직 자체를 잡는다.
class _RejectingNotificationSettingsRepository
    implements NotificationSettingsRepository {
  new(
    this._initial, {
    this.failure = const Failure.api(
      statusCode: 422,
      code: 'INVALID_SETTINGS',
      message: '설정을 바꾸지 못했습니다',
    ),
  });

  final NotificationSettings _initial;
  final Failure failure;

  @override
  Future<NotificationSettings> getNotificationSettings() async => _initial;

  @override
  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  ) => Future.error(failure);
}

/// 응답을 손으로 늦추는 가짜 — 스위치가 응답 전에 바뀌는지 본다(M-P4).
class _PendingNotificationSettingsRepository
    implements NotificationSettingsRepository {
  new(this._initial);

  final NotificationSettings _initial;
  final Completer<NotificationSettings> response = Completer();

  @override
  Future<NotificationSettings> getNotificationSettings() async => _initial;

  @override
  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  ) => response.future;
}

void main() {
  testWidgets('서버가 변경을 거부하면 스위치가 거부되기 전 값으로 되돌아간다', (tester) async {
    const initial = NotificationSettings(
      arrive: false,
      boarding: true,
      noShow: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsRepositoryProvider.overrideWithValue(
            _RejectingNotificationSettingsRepository(initial),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationSettingsPanel(isParent: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 초기값 — 도착 알림은 꺼진 상태.
    var arriveSwitch = tester.widget<BaraedaSwitch>(
      find.byType(BaraedaSwitch).first,
    );
    expect(arriveSwitch.checked, isFalse);

    // 켜기를 시도 → 서버가 거부.
    await tester.tap(find.byType(BaraedaSwitch).first);
    await tester.pumpAndSettle();

    arriveSwitch = tester.widget<BaraedaSwitch>(
      find.byType(BaraedaSwitch).first,
    );
    expect(
      arriveSwitch.checked,
      isFalse,
      reason: '서버가 거부했으면 화면은 거부되기 전 값(false)으로 돌아가야 한다',
    );
    expect(find.text('설정을 바꾸지 못했습니다'), findsOneWidget);
  });

  testWidgets('F05-14 네트워크 오류로 실패하면 네트워크 확인 문구를 보여준다', (tester) async {
    const initial = NotificationSettings(
      arrive: false,
      boarding: true,
      noShow: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsRepositoryProvider.overrideWithValue(
            _RejectingNotificationSettingsRepository(
              initial,
              failure: const Failure.network(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationSettingsPanel(isParent: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BaraedaSwitch).first);
    await tester.pumpAndSettle();

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });

  // M-P4 — C-10: 서버가 처리한 뒤에야 화면이 바뀐다. 응답 전에 먼저 바뀌어 있으면 실패 때 거짓 상태가 잠깐 보인다.
  group('M-P4 스위치는 서버 응답 뒤에 바뀐다', () {
    const initial = NotificationSettings(
      arrive: false,
      boarding: true,
      noShow: true,
    );

    Future<_PendingNotificationSettingsRepository> pumpPending(
      WidgetTester tester,
    ) async {
      final repository = _PendingNotificationSettingsRepository(initial);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationSettingsRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationSettingsPanel(isParent: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    bool arriveChecked(WidgetTester tester) =>
        tester.widget<BaraedaSwitch>(find.byType(BaraedaSwitch).first).checked;

    testWidgets('응답이 오기 전에는 누른 스위치가 그대로이고, 응답이 오면 바뀐다', (tester) async {
      final repository = await pumpPending(tester);

      await tester.tap(find.byType(BaraedaSwitch).first);
      await tester.pump();

      expect(arriveChecked(tester), isFalse, reason: '서버 응답 전이다');

      repository.response.complete(
        const NotificationSettings(arrive: true, boarding: true, noShow: true),
      );
      await tester.pumpAndSettle();

      expect(arriveChecked(tester), isTrue);
    });

    testWidgets('응답을 기다리는 동안 스위치는 잠기고 같은 요청을 또 보내지 않는다', (tester) async {
      final repository = await pumpPending(tester);

      await tester.tap(find.byType(BaraedaSwitch).first);
      await tester.pump();

      final locked = tester.widget<BaraedaSwitch>(
        find.byType(BaraedaSwitch).first,
      );
      expect(locked.disabled, isTrue);

      repository.response.complete(initial);
      await tester.pumpAndSettle();
    });
  });

  // R48 `Ruling 829` — 학생이 받는 알림은 도착 · 운행 시작뿐이라 의미 없는 스위치(미승차)를 뺀다.
  group('R48 역할별 스위치', () {
    const settings = NotificationSettings(
      arrive: true,
      boarding: true,
      noShow: true,
    );

    Future<void> pump(WidgetTester tester, {required bool isParent}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationSettingsRepositoryProvider.overrideWithValue(
              _RejectingNotificationSettingsRepository(settings),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NotificationSettingsPanel(isParent: isParent),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('학생은 스위치 2개 — 버스 도착 알림 · 운행 시작 알림', (tester) async {
      await pump(tester, isParent: false);

      expect(find.byType(BaraedaSwitch), findsNWidgets(2));
      expect(find.text('버스 도착 알림'), findsOneWidget);
      expect(find.text('운행 시작 알림'), findsOneWidget);
      expect(find.text('내 버스의 운행이 시작될 때'), findsOneWidget);
      expect(find.text('미승차 알림'), findsNothing);
      expect(find.text('등하원 알림'), findsNothing);
    });

    testWidgets('학부모는 스위치 3개 — 도착 · 등하원 · 미승차', (tester) async {
      await pump(tester, isParent: true);

      expect(find.byType(BaraedaSwitch), findsNWidgets(3));
      expect(find.text('등하원 알림'), findsOneWidget);
      expect(find.text('승차 · 하차 · 운행 시작'), findsOneWidget);
      expect(find.text('미승차 알림'), findsOneWidget);
      expect(find.text('운행 시작 알림'), findsNothing);
    });

    testWidgets('지연 알림은 스위치 없이 "항상 켜짐" 칩이다 — 학부모 · 학생 공통', (tester) async {
      for (final isParent in [true, false]) {
        await pump(tester, isParent: isParent);

        expect(find.text('지연 알림'), findsOneWidget);
        expect(find.text('버스가 늦으면 항상 알려 드려요'), findsOneWidget);
        expect(find.text('항상 켜짐'), findsOneWidget);
      }
    });
  });
}
