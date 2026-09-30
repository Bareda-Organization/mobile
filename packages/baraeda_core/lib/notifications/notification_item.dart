import 'package:baraeda_core/id/as_id_string.dart';

/// `GET /notifications` 응답 항목 (API_SPEC §3.12).
///
/// [type] 은 §9.7 알림 종류를 문자열 그대로 보관한다 — 종류별 모양·이동 화면은
/// 각 앱의 `notification_kind.dart` 가 한 곳에서 정하고, 전체 목록을 enum 으로 옮기면
/// §9.7 이 늘 때마다 이 파일도 고쳐야 하는 결합이 생긴다.
class NotificationItem {
  /// 응답 한 항목을 그대로 담는다.
  const NotificationItem({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.body,
    required this.sentAt,
    required this.popup,
    this.studentId,
    this.studentName,
    this.readAt,
  });

  /// §3.12 응답 항목 JSON 에서 만든다.
  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        notificationId: asIdString(json['notification_id']),
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        studentId: json['student_id'] == null
            ? null
            : asIdString(json['student_id']),
        studentName: json['student_name'] as String?,
        sentAt: DateTime.parse(json['sent_at'] as String),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
        popup: json['popup'] as bool,
      );

  /// 알림 식별자 — 읽음 처리(§3.13)의 경로 변수.
  final String notificationId;

  /// §9.7 알림 종류 문자열.
  final String type;

  /// 자녀 이름 필수 포함(ATT-03).
  final String title;

  /// 본문.
  final String body;

  /// 대상 자녀 식별자(자녀와 무관한 알림이면 `null`).
  final String? studentId;

  /// 대상 자녀 이름.
  final String? studentName;

  /// 발송 시각.
  final DateTime sentAt;

  /// `null` 이면 미읽음.
  final DateTime? readAt;

  /// 팝업 노출 대상 여부(NTF-09).
  final bool popup;

  /// 아직 읽지 않았는가.
  bool get isUnread => readAt == null;

  /// 읽음 처리한 사본 — 목록을 다시 받지 않고 그 행만 읽음으로 바꾼다.
  NotificationItem markedRead(DateTime at) => NotificationItem(
    notificationId: notificationId,
    type: type,
    title: title,
    body: body,
    sentAt: sentAt,
    popup: popup,
    studentId: studentId,
    studentName: studentName,
    readAt: at,
  );
}

/// §3.12 페이징 봉투(§1.8) + 봉투 레벨 `unread_count`.
class NotificationPage {
  /// 봉투 한 쪽을 그대로 담는다.
  const NotificationPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalCount,
    required this.hasNext,
    required this.unreadCount,
  });

  /// §3.12 응답 JSON 에서 만든다.
  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>? ?? [];
    return NotificationPage(
      items: items
          .cast<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList(),
      page: json['page'] as int,
      size: json['size'] as int,
      totalCount: json['total_count'] as int,
      hasNext: json['has_next'] as bool,
      unreadCount: json['unread_count'] as int,
    );
  }

  /// 이 쪽의 알림.
  final List<NotificationItem> items;

  /// 쪽 번호(0부터).
  final int page;

  /// 쪽 크기.
  final int size;

  /// 걸러 본 조건에 맞는 전체 건수.
  final int totalCount;

  /// 다음 쪽이 있는가.
  final bool hasNext;

  /// 미읽음 배지용 — 봉투 레벨(§3.12).
  final int unreadCount;
}
