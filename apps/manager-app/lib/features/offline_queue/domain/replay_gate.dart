/// 로그아웃이 시작된 뒤 대기열 재생이 새로 시작되지 않게 막는 빗장(R56 · R55 ③).
///
/// 로그아웃이 시작되고 대기열이 비워지기까지 사이에 30초 자동 재생 · 쓰기 직전 재생 · 수동 재시도가 시작되면
/// 앞 계정의 처리가 전송된다. 로그아웃이 [pause] 하고, 대기열이 비워지거나 새로 로그인하면 [resume] 한다.
/// 이미 나간 요청 1건은 막을 수 없다.
class ReplayGate {
  var _paused = false;

  /// 재생을 시작하거나 다음 행을 보내도 되는가의 반대 — 참이면 보내지 않는다.
  bool get isPaused => _paused;

  void pause() => _paused = true;

  void resume() => _paused = false;
}
