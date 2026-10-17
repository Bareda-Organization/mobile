import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/features/settings/data/notification_settings_api.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/domain/notification_settings_repository.dart';

/// [NotificationSettingsRepository] 의 `data` 계층 구현 — 다른 repository
/// 와 같은 `_guard`(DioException → Failure) 패턴
/// (`change_request_repository_impl.dart` 참고).
class NotificationSettingsRepositoryImpl
    implements NotificationSettingsRepository {
  const new({required this._notificationSettingsApi});

  final NotificationSettingsApi _notificationSettingsApi;

  @override
  Future<NotificationSettings> getNotificationSettings() =>
      guardDio(_notificationSettingsApi.getNotificationSettings);

  @override
  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  ) => guardDio(
    () => _notificationSettingsApi.updateNotificationSettings(settings),
  );
}
