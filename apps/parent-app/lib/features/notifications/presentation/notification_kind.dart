import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:parent_app/app/app_routes.dart';

/// 종류 → 목록 모양. 운행·승하차·도착·지연은 실시간 지도(UF-P-07), 변경 결과는 일정 화면의 신청 이력(UF-P-06).
///
/// ⚠ **모르는 종류를 초록으로 떨어뜨리지 않는다.** §9.7 은 앞으로도 늘고, 새 종류가 초록 '승차'로 보이면
/// `no_show`(버스가 왔는데 아이가 안 나온 사고)도 정상으로 읽힌다 — 2026-09-21 까지 모든 알림이 그 상태였다.
NotificationKind kindOf(String type) => switch (type) {
  'boarding' => const NotificationKind(
    icon: 'log-in',
    status: BaraedaStatus.boarded,
    label: '승차',
    route: AppRoutes.liveMap,
  ),
  'alighting' => const NotificationKind(
    icon: 'log-out',
    status: BaraedaStatus.boarded,
    label: '하차',
    route: AppRoutes.liveMap,
  ),
  // 폐지된 종류(Ruling 308) — 과거 발송분만 남아 있다.
  'boarding_canceled' => const NotificationKind(
    icon: 'x',
    status: BaraedaStatus.idle,
    label: '승차 취소',
    route: AppRoutes.liveMap,
  ),
  'alighting_canceled' => const NotificationKind(
    icon: 'x',
    status: BaraedaStatus.idle,
    label: '하차 취소',
    route: AppRoutes.liveMap,
  ),
  'no_show' => const NotificationKind(
    icon: 'user-x',
    status: BaraedaStatus.missed,
    label: '미승차',
    important: true,
    route: AppRoutes.liveMap,
  ),
  'arrive' => const NotificationKind(
    icon: 'map-pin',
    status: BaraedaStatus.moving,
    label: '곧 도착',
    route: AppRoutes.liveMap,
  ),
  'delay' => const NotificationKind(
    icon: 'clock',
    status: BaraedaStatus.moving,
    label: '지연',
    important: true,
    route: AppRoutes.liveMap,
  ),
  'run_started' => const NotificationKind(
    icon: 'bus',
    status: BaraedaStatus.moving,
    label: '운행 시작',
    route: AppRoutes.liveMap,
  ),
  'route_changed' => const NotificationKind(
    icon: 'route',
    status: BaraedaStatus.moving,
    label: '노선 변경',
    important: true,
    route: AppRoutes.liveMap,
  ),
  'change_decided' => const NotificationKind(
    icon: 'calendar-check',
    status: BaraedaStatus.idle,
    label: '변경 결과',
    route: AppRoutes.schedule,
  ),
  'signup_decided' => const NotificationKind(
    icon: 'user-plus',
    status: BaraedaStatus.idle,
    label: '가입 결과',
  ),
  'emergency' => const NotificationKind(
    icon: 'triangle-alert',
    status: BaraedaStatus.missed,
    label: '비상',
  ),
  'emergency_canceled' => const NotificationKind(
    icon: 'circle-check',
    status: BaraedaStatus.idle,
    label: '비상 해제',
  ),
  _ => const NotificationKind(
    icon: 'bell',
    status: BaraedaStatus.idle,
    label: '안내',
  ),
};
