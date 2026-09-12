/// §4.8 `attempt_type`.
enum NoShowAttemptType {
  call('call'),
  message('message');

  const NoShowAttemptType(this.wireValue);

  final String wireValue;
}

/// §4.8 `result`.
enum NoShowContactResult {
  answered('answered'),
  noAnswer('no_answer');

  const NoShowContactResult(this.wireValue);

  final String wireValue;
}

/// §4.8 `decision` — 3분 경과 후 최종 판단. 그 전에는 미전달.
enum NoShowDecision {
  depart('depart'),
  retry('retry');

  const NoShowDecision(this.wireValue);

  final String wireValue;
}

/// `POST /runs/{runId}/riders/{riderId}/no-show-contacts` 요청 본문 — §4.8.
/// 응답 필드가 사양에 명시되지 않아(§4.8, 에러 코드만 정의) 요청 성공 여부만
/// 반환한다(repository 는 `Future<void>`).
class NoShowContactRequest {
  const NoShowContactRequest({
    required this.attemptType,
    required this.result,
    this.decision,
  });

  Map<String, dynamic> toJson() => {
    'attempt_type': attemptType.wireValue,
    'result': result.wireValue,
    if (decision != null) 'decision': decision!.wireValue,
  };

  final NoShowAttemptType attemptType;
  final NoShowContactResult result;
  final NoShowDecision? decision;
}
