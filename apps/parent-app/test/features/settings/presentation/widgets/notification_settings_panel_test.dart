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
  _RejectingNotificationSettingsRepository(
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
          home: Scaffold(body: NotificationSettingsPanel()),
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
          home: Scaffold(body: NotificationSettingsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BaraedaSwitch).first);
    await tester.pumpAndSettle();

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });
}
