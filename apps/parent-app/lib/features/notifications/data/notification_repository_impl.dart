import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/features/notifications/data/notification_api.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';
import 'package:parent_app/features/notifications/domain/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
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
