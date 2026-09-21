import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';

/// §3.12 파싱 시험 — `isUnread` 는 화면 뱃지가 직접 참조하는 파생값이라
/// `read_at` null 처리가 어긋나면 읽은 알림이 안 읽은 것으로 보인다.
void main() {
  test('NotificationItem.isUnread 는 read_at 이 없으면 true 다', () {
    final item = NotificationItem.fromJson({
      'notification_id': 'n-1',
      'type': 'boarding',
      'title': '승하차 안내',
      'body': '김철수 학생이 버스에 탑승했습니다.',
      'sent_at': '2026-09-12T00:00:00Z',
      'read_at': null,
      'popup': false,
    });

    expect(item.isUnread, isTrue);
  });

  test('NotificationItem.isUnread 는 read_at 이 있으면 false 다', () {
    final item = NotificationItem.fromJson({
      'notification_id': 'n-2',
      'type': 'alighting',
      'title': '승하차 안내',
      'body': '김철수 학생이 버스에서 하차했습니다.',
      'sent_at': '2026-09-12T00:00:00Z',
      'read_at': '2026-09-12T00:05:00Z',
      'popup': false,
    });

    expect(item.isUnread, isFalse);
  });

  test('NotificationPage.fromJson 은 봉투 레벨 unread_count 를 함께 읽는다', () {
    final page = NotificationPage.fromJson({
      'items': <dynamic>[],
      'page': 0,
      'size': 20,
      'total_count': 0,
      'has_next': false,
      'unread_count': 3,
    });

    expect(page.unreadCount, 3);
    expect(page.items, isEmpty);
  });
}
