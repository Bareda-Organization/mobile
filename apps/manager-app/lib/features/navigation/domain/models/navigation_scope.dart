/// `GET /runs/{runId}/navigation` 의 `scope` 값(API_SPEC §4.16) — 서버가 몇 곳까지 내비에 넘길지의 기준이다.
enum NavigationScope {
  /// 다음 목적지 1곳만.
  next,

  /// 남은 전 구간 — 서버가 공급자 상한까지 잘라 준다.
  remaining,
}
