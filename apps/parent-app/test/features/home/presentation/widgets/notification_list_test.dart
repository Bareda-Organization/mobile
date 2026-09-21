import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/widgets/notification_list.dart';

final _sentAt = DateTime(2026, 9, 21, 8, 30);

NotificationPage _pageOf(String type, String title) => NotificationPage(
  items: [
    NotificationItem(
      notificationId: 'n-1',
      type: type,
      title: title,
      body: '본문',
      sentAt: _sentAt,
      popup: false,
      studentName: '김영희',
    ),
  ],
  page: 1,
  size: 20,
  totalCount: 1,
  hasNext: false,
  unreadCount: 1,
);

Future<BaraedaStatusPill> _pumpAndReadPill(
  WidgetTester tester,
  String type,
  String title,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: NotificationList(
            page: _pageOf(type, title),
            now: _sentAt.add(const Duration(minutes: 3)),
          ),
        ),
      ),
    ),
  );
  return tester.widget<BaraedaStatusPill>(find.byType(BaraedaStatusPill));
}

void main() {
  // 알림 카드의 상태 태그는 **그 알림의 종류**를 말해야 한다.
  //
  // ⚠ 2026-09-21 실측 — 학부모 앱이 태그를 한 번도 넘기지 않아 `NotificationCard`
  // 의 기본값(`BaraedaStatus.boarded` = 초록 '승차 완료')이 **모든 알림에** 붙었다.
  // 하차·지연·노선 변경까지 "승차 완료" 로 보였고, 그중 `no_show`(미승차)는
  // **버스가 왔는데 아이가 안 나온 사고**인데 초록 '승차 완료' 로 표시된다 —
  // 학부모가 사고를 정상으로 읽는다(`FEATURE_SPEC C-02` · C-09 색 규칙).
  testWidgets('미승차 알림은 레드 · "미승차" 로 표시한다', (tester) async {
    final pill = await _pumpAndReadPill(tester, 'no_show', '미승차 안내');

    expect(pill.label, '미승차');
    expect(pill.status, BaraedaStatus.missed);
    expect(find.text('승차 완료'), findsNothing);
  });

  testWidgets('종류마다 다른 태그가 붙는다', (tester) async {
    for (final (type, label, status) in const [
      ('boarding', '승차 완료', BaraedaStatus.boarded),
      ('alighting', '하차 완료', BaraedaStatus.boarded),
      ('arrive', '곧 도착', BaraedaStatus.moving),
      ('delay', '지연', BaraedaStatus.moving),
      ('run_started', '운행 시작', BaraedaStatus.moving),
      ('boarding_canceled', '승차 취소', BaraedaStatus.idle),
    ]) {
      final pill = await _pumpAndReadPill(tester, type, '$label 안내');
      expect(pill.label, label, reason: type);
      expect(pill.status, status, reason: type);
    }
  });

  // §9.7 은 앞으로도 늘어난다 — 모르는 종류가 초록 '승차 완료' 로 떨어지면
  // 새 알림이 추가될 때마다 같은 오표시가 조용히 생긴다.
  testWidgets('모르는 종류는 중립 태그로 떨어진다', (tester) async {
    final pill = await _pumpAndReadPill(tester, 'some_new_type', '안내');

    expect(pill.label, '안내');
    expect(pill.status, BaraedaStatus.idle);
  });
}
