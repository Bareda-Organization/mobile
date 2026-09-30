import 'package:parent_app/core/map/marker_interpolator.dart';

/// 마커 하나가 새 좌표를 받을 때마다 "직전 두 좌표의 수신 간격만큼
/// 균등하게 펴는" 보간 상태를 관리한다.
///
/// **판단 근거 — 왜 고정 시간(600ms) 이 아니라 수신 간격을 쓰는가**
/// (2026-09-14 사용자 결정, `COMMON-B2.md §2`): 위치 전송 주기는
/// 8초→2초로 이미 한 번 바뀌었고 앞으로도 부하 재측정에 따라 되돌아갈
/// 수 있다. 보간 시간을 전송 주기에서 읽으면(=수신 간격을 그대로 쓰면)
/// 주기가 바뀔 때 이 코드를 다시 손댈 필요가 없다.
///
/// **판단 근거 — `DateTime.now()` 를 이 클래스 안에 감추지 않고 매
/// 호출마다 인자로 받는 이유**: 그래야 단위 검사가 실제 시계를 기다리지
/// 않고 임의의 시각을 넣어 "0.5초 지난 시점" 같은 상태를 즉시 재현할
/// 수 있다. 실제 프레임 타이머는 `naver/naver_map_adapter.dart` 가
/// `DateTime.now()` 를 넘겨 호출한다.
class MarkerMotionController {
  MarkerMotionController({
    this.defaultIntervalMs = 2000,
    this.maxIntervalMs = 10000,
  });

  /// 첫 좌표라 직전 수신 간격을 모를 때 쓰는 기본 보간 시간(ms).
  /// 2026-09-14 기준 전송 주기(2초)를 따른다.
  final int defaultIntervalMs;

  /// 이 값을 넘는 수신 간격은 보간하지 않고 즉시 이동한다(ms).
  ///
  /// **판단 근거 — 왜 10초인가**: 통신이 끊겼다 복구되면 간격이 수십
  /// 초로 벌어질 수 있는데, 그 간격 그대로 보간하면 마커가 아주 느리게
  /// 기어가 "멈춘 것"과 구별되지 않는다(`COMMON-B2.md §2` 지시). 정상
  /// 전송 주기(2초, 직전엔 8초)의 5배(=구 주기의 1.25배)를 상한으로
  /// 잡아, 정상 지연 변동은 그대로 보간하면서 통신 두절만 걸러낸다.
  final int maxIntervalMs;

  LatLng? _start;
  LatLng? _end;
  DateTime? _startedAt;
  int _durationMs = 0;
  DateTime? _lastReceivedAt;

  /// 새 좌표가 도착했을 때 부른다.
  void onCoordinateReceived(LatLng target, DateTime now) {
    final previousReceivedAt = _lastReceivedAt;
    _lastReceivedAt = now;

    final currentPosition = currentPositionAt(now);
    if (currentPosition == null) {
      // 첫 좌표 — 보간할 시작점이 없으니 그 자리에 바로 둔다.
      _start = target;
      _end = target;
      _startedAt = now;
      _durationMs = 0;
      return;
    }

    // 좌표가 그대로면 움직일 것이 없다 — 같은 자리에서 같은 자리로 "보간 중" 이 되면 정차지 마커까지 프레임마다
    // 옮기게 된다(R46 D #11).
    if (currentPosition == target) {
      _start = target;
      _end = target;
      _startedAt = now;
      _durationMs = 0;
      return;
    }

    final intervalMs = previousReceivedAt == null
        ? defaultIntervalMs
        : now.difference(previousReceivedAt).inMilliseconds;

    // **이어붙이기** — 새 구간은 좌표가 실제로 향했던 지점(target)이
    // 아니라 "지금 화면에 보이는 위치"에서 시작한다. 그래야 새 좌표가
    // 도착한 순간 마커가 이전 목표로 순간이동했다가 다시 출발하는
    // 것처럼 튀지 않는다.
    _start = currentPosition;
    _end = target;
    _startedAt = now;
    // 상한을 넘으면 durationMs 를 0 으로 둔다 — 아래 currentPositionAt
    // 이 durationMs<=0 일 때 곧바로 end 를 돌려주므로 "보간 없이 즉시
    // 이동"과 같은 효과를 낸다.
    _durationMs = intervalMs > maxIntervalMs ? 0 : intervalMs;
  }

  /// [now] 시점의 보간된 위치. 좌표를 아직 한 번도 받지 못했으면 null.
  LatLng? currentPositionAt(DateTime now) {
    final start = _start;
    final end = _end;
    final startedAt = _startedAt;
    if (start == null || end == null || startedAt == null) return null;
    if (_durationMs <= 0) return end;

    final elapsedMs = now.difference(startedAt).inMilliseconds;
    return MarkerInterpolator.at(
      start: start,
      end: end,
      progress: elapsedMs / _durationMs,
    );
  }

  /// 진행 중인 보간이 아직 끝나지 않았는가 — 어댑터가 프레임 타이머를
  /// 계속 돌릴지 멈출지 판단하는 데 쓴다.
  bool isAnimating(DateTime now) {
    final startedAt = _startedAt;
    if (_start == null || _end == null || startedAt == null) return false;
    if (_durationMs <= 0) return false;
    return now.difference(startedAt).inMilliseconds < _durationMs;
  }
}
