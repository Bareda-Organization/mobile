/// 라우트 경로 상수 — `router.dart` 와 `features/*/presentation` 화면이
/// 함께 참조한다. 상수를 `router.dart` 에 두면 화면이 라우트 문자열을
/// 얻으려고 `router.dart` 를 import 해야 하는데, `router.dart` 는 이미
/// 화면들을 import 하므로 그러면 순환 참조가 된다 — 그래서 이 파일 하나로
/// 뺐다.
///
/// 화면 ↔ 라우트 대응은 IMPLEMENTATION_PLAN.md §3.1 6화면 + §5.0 F2 4화면
/// 중 3개(로그인·회원가입·대기)를 이 목록에 담는다. 차단 안내(UF-X-04)는
/// [blockedAccount] 로 존재하되 `redirect` 가 아니라 로그인 화면이 직접
/// `push` 한다 — `blocked` 는 로그인 자체가 실패해 토큰도 role/status 도
/// 생기지 않으므로 다른 라우트들처럼 provider 값으로 판정할 수 없다
/// (§ 아키텍처 결정 2, 보고서 참고).
abstract final class AppRoutes {
  static const login = '/login';
  static const signup = '/signup';

  /// AUTH-08 · API_SPEC §2.9 — 비인증 진입점(로그인 화면에서만 `push`).
  static const accountRecovery = '/account-recovery';
  static const pendingApproval = '/pending-approval';
  static const blockedAccount = '/blocked-account';
  static const home = '/home';

  /// 알림 탭(P-09 · S-03) — 앱 아래 탭 막대의 두 번째 칸. 푸시로 들어오는 경로도 이 주소다.
  static const notifications = '/notifications';
  static const liveMap = '/live-map';
  static const routeDetail = '/route-detail';
  static const schedule = '/schedule';
  static const settings = '/settings';

  /// AUTH-07 · API_SPEC §2.8 — [settings] 화면에서 `push`.
  static const passwordChange = '/password-change';

  /// 자녀 연결 (FEATURE_SPEC §5.1 색인 기준 P-02, BRIEF 표기 "P-01" 은
  /// 정본과 어긋남 — 보고서 §2 참고) · 학생 코드 생성(S-05).
  static const childLink = '/child-link';
}
