/// `BaraedaWebSocketClient` 의 연결 상태 — 화면이 배지·재연결 안내를 그리는
/// 데 쓴다. 그 클래스는 이 파일이 아니라 `baraeda_websocket_client.dart` 에 있다.
enum WsConnectionState {
  /// 연결 시도 전, 또는 `disconnect()` 호출 이후 — 재연결 타이머도 없다.
  disconnected,

  /// CONNECT 프레임을 보내고 서버 응답을 기다리는 중.
  connecting,

  /// CONNECTED 프레임 수신 — 구독 호출이 가능한 유일한 상태.
  connected,

  /// 연결이 끊겨 백오프 간격만큼 대기 중 — 자동으로 [connecting] 으로 넘어간다.
  reconnecting,

  /// 재시도 횟수 상한 도달 — 더 이상 자동 재연결하지 않는다. 화면이 수동
  /// 재시도 버튼을 보여줘야 하는 상태(§4 판단 근거 — "give-up" 조건).
  gaveUp,
}
