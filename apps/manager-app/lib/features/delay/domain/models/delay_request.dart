/// §4.9 `reason` — 프리셋 4종.
enum DelayReason {
  traffic('traffic'),
  weather('weather'),
  vehicleCheck('vehicle_check'),
  prevStopWait('prev_stop_wait');

  new(this.wireValue);

  final String wireValue;
}

/// `POST /runs/{runId}/delay` 요청 본문 — §4.9. `minutes` 는 5분 단위만
/// 허용(그 외 서버가 `422 VALIDATION_FAILED`) — [DelayPicker](baraeda_ui)
/// 의 기본 옵션(`5,10,15,20,25,30`)이 이미 5분 단위라 클라이언트 쪽 추가
/// 검증은 두지 않는다.
class DelayRequest {
  const new({
    required this.minutes,
    required this.reason,
    this.message,
  });

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    'reason': reason.wireValue,
    if (message != null) 'message': message,
  };

  final int minutes;
  final DelayReason reason;

  /// 프리셋 문구를 수정한 값 — 미전달 시 서버가 `reason` 기반 자동 생성.
  final String? message;
}
