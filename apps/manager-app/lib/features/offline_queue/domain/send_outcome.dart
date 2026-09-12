/// 쓰기 요청 한 건이 어떻게 처리됐는지 — §1.9(낙관적 UI 금지) 를 지키려면
/// "성공"과 "큐에 쌓임" 을 화면이 반드시 구분해야 한다. 서버 2xx 를 아직
/// 못 받았는데 [Sent] 처럼 보이면 낙관적 UI가 되고, 반대로 [Queued] 를
/// [Sent] 로 오인하면 "처리되었습니다" 를 실제로 처리되지 않은 요청에
/// 붙이게 된다.
sealed class SendOutcome<T> {
  const SendOutcome();
}

/// 서버가 2xx 로 응답해 즉시 처리됨 — [value] 는 그 응답을 옮긴 결과.
class Sent<T> extends SendOutcome<T> {
  const Sent(this.value);

  final T value;
}

/// 네트워크 장애로 서버에 닿지 못해 오프라인 큐에 쌓임 — 아직 처리되지
/// 않았다. 화면은 "처리되지 않았습니다 · 대기 중" 을 보여준다(§1.9).
class Queued<T> extends SendOutcome<T> {
  const Queued();
}
