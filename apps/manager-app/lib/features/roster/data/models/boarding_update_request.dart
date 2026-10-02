import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/wire_time.dart';

/// §4.6 `verify_method` — `photo`(사진) · `manual`(명단 육안 확인). 이번
/// 라운드는 카메라 연동을 범위에 두지 않아(스코프 밖, 보고서 참고)
/// [BoardingUpdateRequest] 가 항상 `manual` 로 고정한다.
enum VerifyMethod {
  photo('photo'),
  manual('manual');

  VerifyMethod(this.wireValue);

  final String wireValue;
}

/// `PATCH /runs/{runId}/riders/{riderId}` 요청 본문 — §4.6.
///
/// `status` 는 [RiderStatus] 를 그대로 쓰지만 서버가 받는 값은 `waiting` 을
/// 뺀 3종(`boarded`·`no_show`·`alighted`) 뿐이다 — 호출부(StopRoster
/// 버튼)가 그 3종만 넘기도록 보장하고, 여기서 다시 검증하지 않는다(단일
/// enum 을 새로 만들면 [RiderStatus] 와 값이 갈릴 위험이 더 크다).
class BoardingUpdateRequest {
  const BoardingUpdateRequest({
    required this.status,
    required this.clientKey,
    this.verifyMethod = VerifyMethod.manual,
    this.occurredAt,
  });

  Map<String, dynamic> toJson() => {
    'status': status.wireValue,
    'verify_method': verifyMethod.wireValue,
    'client_key': clientKey,
    if (occurredAt != null) 'occurred_at': toWireTime(occurredAt!),
  };

  final RiderStatus status;
  final VerifyMethod verifyMethod;

  /// 오프라인 큐 멱등키(UUID) — `IdempotencyKeys.generate()` 로 만든다.
  final String clientKey;
  final DateTime? occurredAt;
}
