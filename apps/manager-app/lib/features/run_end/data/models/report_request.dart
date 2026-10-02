/// §4.13 `type` — 현장 상황 보고 4종.
enum ReportType {
  guardianAbsent('guardian_absent'),
  roadBlock('road_block'),
  vehicleIssue('vehicle_issue'),
  etc('etc');

  ReportType(this.wireValue);

  final String wireValue;
}

/// `POST /runs/{runId}/reports` 요청 본문 — §4.13. `riderId` 는
/// `type=guardianAbsent` 일 때 서버가 필수로 요구한다(`422
/// VALIDATION_FAILED`) — 클라이언트는 화면에서 그 경우에만 입력을 받는다.
class ReportRequest {
  const ReportRequest({required this.type, required this.memo, this.riderId});

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    'memo': memo,
    if (riderId != null) 'rider_id': riderId,
  };

  final ReportType type;
  final String memo;
  final String? riderId;
}
