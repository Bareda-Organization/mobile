import 'package:parent_app/features/settings/domain/notification_settings.dart';

/// 화면이 보는 알림 설정 계약 — API_SPEC §3.14.
abstract interface class NotificationSettingsRepository {
  /// `GET` — 설정 화면 진입 시 초기 조회.
  Future<NotificationSettings> getNotificationSettings();

  /// `PATCH` — 항목 하나만 바뀌어도 3개 필드 전부를 다시 보낸다(서버가
  /// 부분 갱신을 지원하지 않음, §3.14 요청 표에 `required` 3개 전부).
  Future<NotificationSettings> updateNotificationSettings(
    NotificationSettings settings,
  );
}
