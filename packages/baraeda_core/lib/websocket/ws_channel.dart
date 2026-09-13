/// STOMP 구독 목적지 빌더 — `API_SPEC §7` 채널 표.
///
/// 표의 `/ws/...` 표기는 채널을 가리키는 이름이고, 실제 SUBSCRIBE 경로는
/// `/topic` 접두사가 붙은 오른쪽 열이다(Ruling 209). 문자열을 호출부마다
/// 직접 조립하면 오타가 조용히 구독 실패(또는 엉뚱한 채널 구독)로 이어지므로
/// 여기 빌더 함수 4개로 고정한다 — 채널은 이 4개뿐이고 앞으로도 늘어나지
/// 않는다(`/ws/location` 하나가 연결 엔드포인트, 나머지는 그 위의 목적지).
class WsChannel {
  const WsChannel._();

  /// 학부모(연결된 자녀)·학생(본인) 전용 — 방송: `position` · `stop_arrived` ·
  /// `run_started` · `run_ended`.
  static String studentRun(String studentId) =>
      '/topic/students/$studentId/run';

  /// 해당 회차에 배치된 기사·동승자 전용 — 방송: `rider_changed` ·
  /// `stop_arrived` · `run_started` · `run_ended` · `emergency_acked`.
  static String managerRun(String runId) => '/topic/manager/runs/$runId';

  /// 해당 학원 관계자 전용 — 방송: `position` · `rider_changed` ·
  /// `stop_arrived` · `run_started` · `run_ended` · `approval_requested` ·
  /// `emergency_raised`.
  static String academyLive(String academyId) =>
      '/topic/academy/$academyId/live';

  /// 메인 관리자 전용 — 방송: `position` · `rider_changed` · `stop_arrived` ·
  /// `run_started` · `run_ended` · `emergency_raised`. 경로 파라미터가 없다.
  static String adminLive() => '/topic/admin/live';
}
