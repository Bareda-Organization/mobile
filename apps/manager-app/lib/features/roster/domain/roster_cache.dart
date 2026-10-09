/// 마지막으로 받은 명단의 로컬 저장소(M-06 · BRD-06 · UF-E-07, `USER_FLOWS §12.2`) —
/// 앱을 다시 켠 뒤 오프라인이어도 명단을 본다. 서버 응답 본문(§4.2)을 그대로 담는다.
abstract interface class RosterCache {
  /// [runId] 회차의 명단 [json] 을 저장한다(앞의 저장본은 덮는다).
  Future<void> save(String runId, Map<String, dynamic> json);

  /// [runId] 회차의 저장본과 저장 시각. 없으면 `null`.
  Future<({Map<String, dynamic> json, DateTime savedAt})?> read(String runId);

  /// 저장본을 모두 지운다 — 로그아웃·세션 만료 때만 부른다. 명단은 계정이 볼 수 있는 학생의 정보라 다음 계정이
  /// 이전 계정의 명단을 보면 안 된다.
  Future<void> clear();
}
