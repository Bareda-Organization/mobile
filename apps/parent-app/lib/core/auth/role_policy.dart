import 'package:parent_app/core/auth/user_role.dart';

/// 역할별 쓰기 권한 판정을 한 곳에 모은다 — 화면 안 `if` 로 흩지 않는다
/// (IMPLEMENTATION_PLAN.md §1.1). 화면은 이 값만 받아 진입점을 감추거나 보인다.
///
/// - 학생은 조회 전용(`UF-S-01`) — 등원 여부 변경 · 탑승 위치 변경 진입점을 감춤
/// - 학생 전용 진입점은 부모 연결 코드 생성(`S-05`) 하나뿐
class RoleCapabilities {
  const new _({
    required this.canToggleAttendance,
    required this.canChangeBoardingLocation,
    required this.canGenerateLinkCode,
  });

  factory of(UserRole role) => switch (role) {
    UserRole.parent => const RoleCapabilities._(
      canToggleAttendance: true,
      canChangeBoardingLocation: true,
      canGenerateLinkCode: false,
    ),
    UserRole.student => const RoleCapabilities._(
      canToggleAttendance: false,
      canChangeBoardingLocation: false,
      canGenerateLinkCode: true,
    ),
  };

  /// 등원 여부(ATT) 변경 — 학부모만.
  final bool canToggleAttendance;

  /// 탑승 위치(승하차지) 변경 — 학부모만.
  final bool canChangeBoardingLocation;

  /// 부모 연결 코드 생성(S-05) — 학생만.
  final bool canGenerateLinkCode;
}
