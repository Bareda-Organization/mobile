import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 알림 권한 요청 포트 — Android 13+ 는 이 권한이 없으면 위치 포그라운드 서비스의
/// "운행 중" 알림이 보이지 않는다(`AndroidManifest.xml` 의 `POST_NOTIFICATIONS`).
/// 시험은 이 포트를 가짜로 덮어 권한 창을 띄우지 않는다.
abstract interface class NotificationPermissionPort {
  /// 권한 창을 띄운다 — 거부돼도 운행 시작을 막지 않으므로 결과를 돌려주지 않는다.
  Future<void> request();
}

/// `permission_handler` 로 실제 권한을 요청한다. 권한 창이 필요한 것은 Android 뿐이다.
class PermissionHandlerNotificationPort implements NotificationPermissionPort {
  @override
  Future<void> request() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await Permission.notification.request();
  }
}
