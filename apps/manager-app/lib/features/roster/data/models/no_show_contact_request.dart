/// §4.8 `attempt_type`.
enum NoShowAttemptType {
  call('call'),
  message('message');

  new(this.wireValue);

  /// 서버가 모르는 값을 주면 `null` — 이력 한 줄 때문에 명단 전체를 못 그리지 않는다.
  static NoShowAttemptType? fromWireValueOrNull(String? value) {
    for (final type in NoShowAttemptType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }

  final String wireValue;
}

/// §4.8 `result`.
enum NoShowContactResult {
  answered('answered'),
  noAnswer('no_answer');

  new(this.wireValue);

  static NoShowContactResult? fromWireValueOrNull(String? value) {
    for (final result in NoShowContactResult.values) {
      if (result.wireValue == value) return result;
    }
    return null;
  }

  final String wireValue;
}

/// §4.8 `decision` — 3분 경과 후 최종 판단. 그 전에는 미전달.
enum NoShowDecision {
  depart('depart'),
  retry('retry');

  new(this.wireValue);

  final String wireValue;
}

/// `POST /runs/{runId}/riders/{riderId}/no-show-contacts` 요청 본문 — §4.8.
/// 응답 필드가 사양에 명시되지 않아(§4.8, 에러 코드만 정의) 요청 성공 여부만
/// 반환한다(repository 는 `Future<void>`).
///
/// 통신 두절이면 오프라인 큐에 쌓였다가 재생되므로(R56 · Ruling 894 ⑧) [clientKey] 를 요청마다 한 번 만들어
/// 즉시 전송과 재생이 같은 값을 쓴다 — 서버가 같은 키 재전송을 중복으로 무시한다(§1.7).
class NoShowContactRequest {
  const new({
    required this.attemptType,
    required this.result,
    required this.clientKey,
    this.decision,
  });

  Map<String, dynamic> toJson() => {
    'attempt_type': attemptType.wireValue,
    'result': result.wireValue,
    'client_key': clientKey,
    if (decision != null) 'decision': decision!.wireValue,
  };

  final NoShowAttemptType attemptType;
  final NoShowContactResult result;

  /// 오프라인 큐 멱등키(UUID) — `IdempotencyKeys.generate()` 로 만든다.
  final String clientKey;
  final NoShowDecision? decision;
}
