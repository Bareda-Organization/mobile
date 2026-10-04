/// 라우트 경로 상수 — `router.dart` 와 `features/*/presentation` 화면이
/// 함께 참조한다. 상수를 `router.dart` 에 두면 화면이 라우트 문자열을
/// 얻으려고 `router.dart` 를 import 해야 하는데, `router.dart` 는 이미
/// 화면들을 import 하므로 그러면 순환 참조가 된다 — 그래서 이 파일 하나로
/// 뺐다(`parent_app` 과 같은 이유, `AppRoutes` 는 앱마다 따로 둔다).
///
/// 화면 ↔ 라우트 대응은 IMPLEMENTATION_PLAN.md §3.2 7화면 +
/// docs/archive/rounds/fe-phases-f2-f5.md §5.0 F2 4화면
/// 중 3개(로그인·회원가입·대기)를 이 목록에 담는다. 차단 안내(UF-X-04)는
/// [blockedAccount] 로 존재하되 `redirect` 가 아니라 로그인 화면이 직접
/// `push` 한다 — `blocked` 는 로그인 자체가 실패해 토큰도 role/status 도
/// 생기지 않으므로 다른 라우트들처럼 provider 값으로 판정할 수 없다
/// (`parent_app` § 아키텍처 결정 2 와 동일).
abstract final class AppRoutes {
  static const login = '/login';
  static const signup = '/signup';
  static const pendingApproval = '/pending-approval';
  static const blockedAccount = '/blocked-account';

  /// 아래 탭 4칸 — 동승자만 명단 탭이 있다. 탭 화면은 `StatefulShellRoute` 안에 있다.
  static const roster = '/roster';
  static const home = '/home';
  static const notifications = '/notifications';
  static const me = '/me';

  /// 운행 준비(기사, `Ruling 799`) — 노선 미리보기 · 승하차지 · [운행 시작].
  static const runReady = '/run-ready';

  /// 기사가 운행 화면에서 여는 조회 전용 명단 — 탭이 아니라 위에 덮여 열린다.
  static const rosterView = '/roster-view';
  static const driveMode = '/drive-mode';

  /// 미승차 연락 — 쿼리 `rider` 로 학생을 가리킨다.
  static const noShow = '/no-show';

  /// 현장 상황 보고 · 보호자 부재 보고(§4.13).
  static const report = '/report';
  static const reportGuardian = '/report-guardian';
  static const delay = '/delay';
  static const routeMap = '/route-map';
  static const runEnd = '/run-end';
  static const emergency = '/emergency';
  static const offlineQueue = '/offline-queue';
  static const passwordChange = '/password-change';
}
