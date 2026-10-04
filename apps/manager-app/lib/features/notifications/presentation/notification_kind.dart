import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:manager_app/app/app_routes.dart';

/// 매니저(기사·동승자)가 받는 알림 종류(`API_SPEC §9.7` 수신자 열) → 목록 모양.
///
/// 받는 종류는 `route_changed`(확정 노선 변경, NTF-10 중요) ·
/// `assignment_changed`(당일 배치 변경) · `signup_decided`(가입 승인·거절) 셋이다.
/// 눌렀을 때 갈 화면은 [destinationOf] 가 정한다 — 알림이 회차 식별자(`run_id`, Ruling 542)를 실어 오는
/// 노선·배치 변경 알림만 그 회차의 화면으로 간다. 모르는 종류는 안내(스톤) 모양으로 두어 초록 '완료'로
/// 오인되지 않게 한다.
NotificationKind kindOf(String type) => switch (type) {
  'route_changed' => const NotificationKind(
    icon: 'route',
    status: BaraedaStatus.moving,
    label: '노선 변경',
    important: true,
  ),
  'assignment_changed' => const NotificationKind(
    icon: 'users-round',
    status: BaraedaStatus.moving,
    label: '배치 변경',
  ),
  'signup_decided' => const NotificationKind(
    icon: 'user-plus',
    status: BaraedaStatus.idle,
    label: '가입 결과',
  ),
  _ => const NotificationKind(
    icon: 'bell',
    status: BaraedaStatus.idle,
    label: '안내',
  ),
};

/// 알림을 눌렀을 때 갈 화면 경로 — 가리킬 화면이 없는 종류는 `null`(읽음 처리만 한다).
///
/// 노선 변경 · 배치 변경 모두 기사는 **운행 준비**로 간다(`Ruling 799` — 바뀐 노선을 확인하고 시작하는 자리),
/// 동승자는 명단 탭으로 간다.
String? destinationOf(String type, {required bool canOperateRun}) =>
    switch (type) {
      'route_changed' || 'assignment_changed' =>
        canOperateRun ? AppRoutes.runReady : AppRoutes.roster,
      _ => null,
    };
