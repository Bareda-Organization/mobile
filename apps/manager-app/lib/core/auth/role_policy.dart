import 'package:manager_app/core/auth/user_role.dart';

/// 역할별 조작 권한 판정을 한 곳에 모은다 — 화면 안 `if` 로 흩지 않는다
/// (IMPLEMENTATION_PLAN.md §1.1). 같은 `StopRoster` 화면에서 버튼 노출이
/// 갈리는 것도 이 값 하나로 판정한다.
///
/// - 버스기사(`driver`): 도착·지연 알림 전송
/// - 동승자(`escort`): 개인별 승하차 상태 결정
class RoleCapabilities {
  const RoleCapabilities._({
    required this.canSendArrivalNotification,
    required this.canSendDelayNotification,
    required this.canDecideBoardingStatus,
  });

  factory RoleCapabilities.of(UserRole role) => switch (role) {
    UserRole.driver => const RoleCapabilities._(
      canSendArrivalNotification: true,
      canSendDelayNotification: true,
      canDecideBoardingStatus: false,
    ),
    UserRole.escort => const RoleCapabilities._(
      canSendArrivalNotification: false,
      canSendDelayNotification: false,
      canDecideBoardingStatus: true,
    ),
  };

  /// 도착 알림 전송 — 기사만.
  final bool canSendArrivalNotification;

  /// 지연 알림 전송 — 기사만.
  final bool canSendDelayNotification;

  /// 개인별 승하차 상태 결정 — 동승자만.
  final bool canDecideBoardingStatus;
}
