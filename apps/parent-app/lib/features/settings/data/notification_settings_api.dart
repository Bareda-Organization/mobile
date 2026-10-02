import 'package:dio/dio.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';

/// API_SPEC §3.14.
class NotificationSettingsApi {
  new({required this._dio});

  final Dio _dio;

  Future<NotificationSettings> getNotificationSettings() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/notification-settings',
    );
    return NotificationSettings.fromJson(response.data!);
  }

  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/me/notification-settings',
      data: settings.toJson(),
    );
    return NotificationSettings.fromJson(response.data!);
  }
}
