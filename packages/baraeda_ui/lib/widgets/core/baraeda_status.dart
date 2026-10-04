// 상태 5종 — `CONVENTIONS_FLUTTER.md §3` "상태 색 매핑은 한 곳에서만 정한다"의
// 대상은 `theme/baraeda_colors.dart`이고, 이 enum은 그 매핑을 참조하는 위젯들
// ([BaraedaStatusPill], [BaraedaCard]의 accent)이 상태를 문자열이 아니라
// 타입으로 주고받게 한다.

/// 운행 상태. 세 제품(학부모·기사·매니저 앱)에서 항상 같은 색 · 같은 모양으로 표시한다.
///
/// 시안 kit "상태 칩 5종" — 종료 ■ · 이동 중 ▶ · 확정 ● · 대기 ○ · 위험 ▲.
/// 색만으로 가르지 않도록 상태마다 [shape] 가 다르다.
enum BaraedaStatus {
  /// 확정 · 승차 완료 · 정상 운행 — 그린 ●.
  boarded,

  /// 이동 중 · 도착 지연 — 앰버 ▶.
  moving,

  /// 미탑승 · 긴급 — 레드 ▲. 화면당 한 번만 노출한다.
  missed,

  /// 운행 전 · 종료 · **미등원**(회색 끝남) — 스톤 ■.
  idle,

  /// 대기 · 확정 전 — 옅은 초록 면 + 테두리 ○.
  waiting,
}

/// 칩 맨 앞에 그리는 모양.
enum BaraedaStatusShape { square, triangleRight, circle, ring, triangleUp }

/// 상태별 기본 문구. `StatusPill` 이 문구를 받지 못했을 때 쓴다.
/// 값의 정본은 디자인 시스템 `components/core/StatusPill.jsx` 의 `statusMeta` 다.
extension BaraedaStatusLabel on BaraedaStatus {
  /// 예: `BaraedaStatus.boarded.label` == `'승차 완료'`.
  String get label => switch (this) {
    BaraedaStatus.boarded => '승차 완료',
    BaraedaStatus.moving => '이동 중',
    BaraedaStatus.missed => '미탑승',
    BaraedaStatus.idle => '운행 전',
    BaraedaStatus.waiting => '대기',
  };
}

/// 상태 → 모양. 색은 `BaraedaColors` 의 `shape*` 가 정한다.
extension BaraedaStatusShapeOf on BaraedaStatus {
  BaraedaStatusShape get shape => switch (this) {
    BaraedaStatus.idle => BaraedaStatusShape.square,
    BaraedaStatus.moving => BaraedaStatusShape.triangleRight,
    BaraedaStatus.boarded => BaraedaStatusShape.circle,
    BaraedaStatus.waiting => BaraedaStatusShape.ring,
    BaraedaStatus.missed => BaraedaStatusShape.triangleUp,
  };
}
