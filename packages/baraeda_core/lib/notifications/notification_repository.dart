import 'package:baraeda_core/network/dio_error_mapper.dart';
import 'package:baraeda_core/notifications/notification_api.dart';
import 'package:baraeda_core/notifications/notification_item.dart';
import 'package:dio/dio.dart';

/// 화면이 보는 알림 계약 — §3.12·§3.13. §1.8 페이징을 그대로 노출한다.
abstract interface class NotificationRepository {
  /// §3.12. [page] 기본 0, [size] 기본 20(최대 100). [unreadOnly] 는 `unread_only` —
  /// 걸러도 봉투의 `unread_count` 는 전체 기준이다.
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  });

  /// §3.13 — 성공 시 `204`(반환값 없음).
  Future<void> markRead(String notificationId);
}

/// [NotificationApi] 를 [NotificationRepository] 에 묶는다.
/// `DioException` 은 `Failure` 로 바꿔 던진다.
class NotificationRepositoryImpl implements NotificationRepository {
  /// [_notificationApi] 를 감싼다.
  const NotificationRepositoryImpl({required this._notificationApi});

  final NotificationApi _notificationApi;

  @override
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) => _guard(
    () => _notificationApi.getNotifications(
      page: page,
      size: size,
      unreadOnly: unreadOnly,
    ),
  );

  @override
  Future<void> markRead(String notificationId) =>
      _guard(() => _notificationApi.markRead(notificationId));

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계 — dart:core 예외 체계를
      // 흉내 내지 않는다). 이 지점의 `only_throw_errors` 는 예외로 둔다.
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
