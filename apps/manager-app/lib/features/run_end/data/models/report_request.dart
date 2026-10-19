/// §4.13 `type` — 현장 상황 보고 4종.
enum ReportType {
  guardianAbsent('guardian_absent'),
  roadBlock('road_block'),
  vehicleIssue('vehicle_issue'),
  etc('etc');

  new(this.wireValue);

  final String wireValue;
}

/// `POST /runs/{runId}/reports` 요청 본문 — §4.13. `riderId` 는
/// `type=guardianAbsent` 일 때 서버가 필수로 요구한다(`422
/// VALIDATION_FAILED`) — 클라이언트는 화면에서 그 경우에만 입력을 받는다.
///
/// 통신 두절이면 오프라인 큐에 쌓였다가 재생되므로(Ruling 894 ⑧) [clientKey] 를 요청마다 한 번 만들어 즉시
/// 전송과 재생이 같은 값을 쓴다 — 서버가 같은 키 재전송을 중복으로 무시한다(§1.7).
class ReportRequest {
  const new({
    required this.type,
    required this.memo,
    required this.clientKey,
    this.riderId,
  });

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    'memo': memo,
    'client_key': clientKey,
    if (riderId != null) 'rider_id': riderId,
  };

  final ReportType type;
  final String memo;

  /// 오프라인 큐 멱등키(UUID) — `IdempotencyKeys.generate()` 로 만든다.
  final String clientKey;
  final String? riderId;
}
