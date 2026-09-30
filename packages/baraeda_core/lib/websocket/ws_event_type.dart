/// `API_SPEC §7` 공통 봉투의 `event` 필드 — 채널 4종이 방송하는 이벤트 10종
/// (§7.1 9종 + `route_changed`). `AccountStatus` 와 같은
/// `wireValue` + `fromWireValueOrNull` 형태를 따른다.
enum WsEventType {
  /// 5~10초 주기 위치 갱신 (`POST /runs/{runId}/position`).
  position('position'),

  /// 기사 도착 처리 (`POST /runs/{runId}/stops/{stopId}/arrive`).
  stopArrived('stop_arrived'),

  /// 탑승 상태 변경 (`PATCH /runs/{runId}/riders/{riderId}` · `revert`).
  riderChanged('rider_changed'),

  /// 운행 시작 (`POST /runs/{runId}/start`).
  runStarted('run_started'),

  /// 운행 종료 — 서버의 `finished` 전이.
  runEnded('run_ended'),

  /// 확정 뒤 노선 변경 — 매니저 채널이 받으면 노선·명단을 다시 조회한다.
  /// ⚠ `API_SPEC §7.1` 에 아직 없다(R36-FE FE6 — 백엔드가 방송을 추가해야 온다).
  routeChanged('route_changed'),

  /// 비상 알림 발신 (`POST /runs/{runId}/emergency`) — 관계자·메인 관리자 채널 전용.
  emergencyRaised('emergency_raised'),

  /// 비상 알림 확인 (`POST /staff/emergencies/{id}/ack`) — 매니저 채널 전용.
  emergencyAcked('emergency_acked'),

  /// 비상 알림 발신 후 1분 안 취소 (`DELETE /runs/{runId}/emergency/{id}`) —
  /// 관계자·메인 관리자 채널 전용(§7.1). 매니저 채널은 받을 일이 없어 무시한다.
  emergencyCanceled('emergency_canceled'),

  /// ②구간 변경 요청 접수 — 관계자 채널 전용.
  approvalRequested('approval_requested');

  const WsEventType(this.wireValue);

  /// 서버 `event` 필드 원문 값.
  final String wireValue;

  /// 모르는 값이면 `null` — 서버가 이벤트를 추가해도 파싱 자체는 죽지 않고,
  /// 이 계층에서 "미지 이벤트"로 갈라져 호출부가 무시하거나 로그만 남길 수
  /// 있다(`WebSocketEnvelope.eventWireValue` 가 원문을 보존한다).
  static WsEventType? fromWireValueOrNull(String? value) {
    for (final type in WsEventType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}
