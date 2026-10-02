import 'package:baraeda_core/notifications/notification_item.dart';
import 'package:dio/dio.dart';

/// API_SPEC §3.12·§3.13.
class NotificationApi {
  /// [_dio] 는 `ApiClient.dio`(인터셉터 부착)를 그대로 받는다.
  new({required this._dio});

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
