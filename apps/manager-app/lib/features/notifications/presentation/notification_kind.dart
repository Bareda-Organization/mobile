import 'package:baraeda_ui/baraeda_ui.dart';

/// 매니저(기사·동승자)가 받는 알림 종류(`API_SPEC §9.7` 수신자 열) → 목록 모양.
///
/// 받는 종류는 `route_changed`(확정 노선 변경, NTF-10 중요) ·
/// `assignment_changed`(당일 배치 변경) · `signup_decided`(가입 승인·거절) 셋이다.
/// **눌렀을 때 갈 화면은 없다** — 알림에 회차 식별자가 없어 관련 화면을 특정할 수 없다
/// (읽음 처리만). 모르는 종류는 안내(스톤) 모양으로 두어 초록 '완료'로 오인되지 않게 한다.
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
