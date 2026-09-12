import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/features/settings/data/notification_settings_api.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/domain/notification_settings_repository.dart';

/// [NotificationSettingsRepository] 의 `data` 계층 구현 — 다른 repository
/// 와 같은 `_guard`(DioException → Failure) 패턴
/// (`change_request_repository_impl.dart` 참고).
class NotificationSettingsRepositoryImpl
    implements NotificationSettingsRepository {
  const NotificationSettingsRepositoryImpl({
    required this._notificationSettingsApi,
  });

  final NotificationSettingsApi _notificationSettingsApi;

  @override
  Future<NotificationSettings> getNotificationSettings() =>
      _guard(_notificationSettingsApi.getNotificationSettings);

  @override
  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  ) => _guard(
    () => _notificationSettingsApi.updateNotificationSettings(settings),
  );

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계).
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
