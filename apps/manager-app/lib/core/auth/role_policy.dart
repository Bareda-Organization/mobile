import 'package:manager_app/core/auth/user_role.dart';

/// 역할별 조작 권한 판정을 한 곳에 모은다 — 화면 안 `if` 로 흩지 않는다
/// (IMPLEMENTATION_PLAN.md §1.1). 같은 `StopRoster` 화면에서 버튼 노출이
/// 갈리는 것도 이 값 하나로 판정한다.
///
/// - 버스기사(`driver`): 운행 시작(§4.4) · 승하차지 도착 처리(§4.5)
/// - 동승자(`escort`): 개인별 승하차 상태 결정(§4.6) · 지연 알림 전송(§4.9)
///
/// ⚠ F2 자리표시 코드는 `canSendDelayNotification` 을 기사=true·동승자=false
/// 로 뒀었다 — API_SPEC §4.9·USER_FLOWS UF-E-05 는 정확히 반대다("기사는
/// 발신 불가", 호출 시 `403 ESCORT_ONLY`). 이번 라운드에서 뒤집었다
/// (F3 M1 보고서 § 우려·판단 근거 항목 참고).
///
/// `canSendArrivalNotification` 은 `canOperateRun` 으로 이름을 바꿨다 — §4.5
/// 는 "이 API 는 알림을 발송하지 않음"이라고 명시한다(도착 예고는 서버가
/// 위치 기반으로 자동 발송, NTF-04). 옛 이름은 이 값이 실제로 게이트하는
/// 동작(운행 시작·도착 처리, 둘 다 기사 전용)과 맞지 않아 바꿨다.
class RoleCapabilities {
  const RoleCapabilities._({
    required this.canOperateRun,
    required this.canSendDelayNotification,
    required this.canDecideBoardingStatus,
    required this.canTransmitPosition,
  });

  factory RoleCapabilities.of(UserRole role) => switch (role) {
    UserRole.driver => const RoleCapabilities._(
      canOperateRun: true,
      canSendDelayNotification: false,
      canDecideBoardingStatus: false,
      canTransmitPosition: true,
    ),
    UserRole.escort => const RoleCapabilities._(
      canOperateRun: false,
      canSendDelayNotification: true,
      canDecideBoardingStatus: true,
      canTransmitPosition: false,
    ),
  };

  /// 운행 시작(§4.4) · 승하차지 도착 처리(§4.5) — 기사만. 동승자 호출 시
  /// 서버는 `403 DRIVER_ONLY` 를 준다.
  final bool canOperateRun;

  /// 지연 알림 전송(§4.9) — 동승자만. 기사 호출 시 `403 ESCORT_ONLY`.
  final bool canSendDelayNotification;

  /// 개인별 승하차 상태 결정(§4.6) — 동승자만. 기사 호출 시 `403 ESCORT_ONLY`.
  final bool canDecideBoardingStatus;

  /// 위치 업로드(§4.12, LOC-01) — 기사만. 동승자 호출 시 서버는
  /// `403 DRIVER_ONLY` 를 준다. `canOperateRun` 과 값이 같지만 게이트하는
  /// 동작이 다른 별개 항목이라 필드를 나눴다 — `canOperateRun` 의 문서
  /// 주석이 대상을 "운행 시작·도착 처리" 로 못 박고 있어, 재사용하면
  /// 위치 업로드가 그 설명 밖의 동작인데도 같은 이름 아래 숨는다.
  final bool canTransmitPosition;
}
