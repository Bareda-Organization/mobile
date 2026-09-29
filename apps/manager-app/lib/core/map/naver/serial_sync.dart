/// 비동기 작업을 한 번에 하나만 돌린다 — 도는 중에 들어온 요청은 모아서 끝난 뒤 한 번만 다시 돈다.
///
/// 지도 오버레이 동기화에 쓴다. 버스 좌표가 2초마다 바뀌어 화면이 다시 그려질 때마다 동기화를 새로
/// 시작하면, 앞선 동기화가 승하차지 핀 이미지를 만드는 도중에 뒤 동기화가 같은 핀을 또 만든다. 그렇게
/// 겹쳐 만든 이미지 중 하나가 빈 파일로 저장되고, 네이버 SDK(iOS)가 그 파일을 읽다 앱이 종료됐다
/// (2026-09-30 시뮬레이터 실측 — `NOverlayImage.makeOverlayImageWithPath`).
class SerialSync {
  SerialSync(this._task);

  final Future<void> Function() _task;
  Future<void>? _running;
  bool _again = false;

  /// 동기화를 요청한다. 이미 도는 중이면 끝난 뒤 한 번 더 돌도록 표시만 하고 그 실행을 기다린다.
  Future<void> request() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _task();
    } while (_again);
  }
}
