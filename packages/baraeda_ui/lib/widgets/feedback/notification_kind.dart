import 'package:baraeda_ui/widgets/core/baraeda_status.dart';

/// 알림 종류(`API_SPEC §9.7`) 하나가 목록에서 갖는 모양과 눌렀을 때 갈 곳.
///
/// 종류 → 모양 표는 앱마다 받는 종류가 달라(학부모·학생 / 기사·동승자) 각 앱이 가진다. 이 값 객체와 그것을
/// 그리는 `NotificationTile`·`NotificationListView` 는 두 앱이 함께 쓴다.
class NotificationKind {
  /// 종류 하나의 모양.
  const new({
    required this.icon,
    required this.status,
    required this.label,
    this.important = false,
    this.route,
  });

  /// `BaraedaIcon` 이름 — 종류마다 달라야 한다. 색만으로 종류를 가르지 않는다.
  final String icon;

  /// 아이콘 원의 색 계열(`FEATURE_SPEC C-09`) — 초록(완료) · 앰버(이동·지연) ·
  /// 레드(미승차·긴급) · 스톤(안내).
  final BaraedaStatus status;

  /// 낭독 전용 종류 이름. 화면에는 나오지 않는다.
  final String label;

  /// 중요 통지 3종(`FEATURE_SPEC NTF-10` — 지연 · 미승차 · 노선 변경).
  final bool important;

  /// 눌렀을 때 갈 화면. 없으면 읽음 처리만 한다.
  final String? route;
}
