import 'package:dio/dio.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';

/// API_SPEC §3.12·§3.13.
class NotificationApi {
  NotificationApi({required this._dio});

  final Dio _dio;

  /// §3.12 — §1.8 페이징(`page` 기본 0 · `size` 기본 20, 최대 100).
  /// `unread_only` 는 켤 때만 보낸다.
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {
        'page': page,
        'size': size,
        if (unreadOnly) 'unread_only': true,
      },
    );
    return NotificationPage.fromJson(response.data!);
  }

  /// §3.13 — `204`.
  Future<void> markRead(String notificationId) async {
    await _dio.patch<void>('/notifications/$notificationId/read');
  }
}
