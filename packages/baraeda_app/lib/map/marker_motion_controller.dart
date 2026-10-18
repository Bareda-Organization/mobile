/// 위경도 좌표 하나. `MapMarker`(공개 계약)와 이름을 겹치지 않게 짧은 record 타입으로 둔다 —
/// 구조적 동등성이 자동으로 생겨 검사에서 `==` 비교가 그대로 통한다.
typedef LatLng = ({double lat, double lng});

/// 지도 마커들이 새 좌표를 받을 때마다 "직전 두 좌표의 수신 간격만큼 균등하게 펴는" 이동을 관리한다 —
/// 마커 id 별 보간 상태, 보간 중인 마커 고르기, 선형 보간 계산까지 이 클래스 하나가 맡는다.
///
/// **왜 고정 시간(600ms) 이 아니라 수신 간격을 쓰는가**: 위치 전송 주기는 8초→2초로 이미 한 번 바뀌었고
/// 부하 재측정에 따라 되돌아갈 수 있다. 보간 시간을 수신 간격에서 읽으면 주기가 바뀔 때 이 코드를 다시
/// 손댈 필요가 없다.
///
/// **왜 `DateTime.now()` 를 감추지 않고 매 호출마다 인자로 받는가**: 단위 검사가 실제 시계를 기다리지 않고
/// 임의의 시각을 넣어 "0.5초 지난 시점" 같은 상태를 즉시 재현하게 하려는 것이다. 이 앱의 위젯 시험은
/// 플랫폼 채널이 없어 지도 SDK 초기화를 검증하지 못하므로, 계산은 SDK 어댑터(`naver/naver_map_adapter.dart`)
/// 밖에 둔다. 어댑터는 프레임마다 `DateTime.now()` 를 넘겨 부른다.
class MarkerMotionController {
  /// 기본 보간 시간 · 상한은 전송 주기(2초) 기준이다.
  new({this.defaultIntervalMs = 2000, this.maxIntervalMs = 10000});

  /// 첫 좌표라 직전 수신 간격을 모를 때 쓰는 기본 보간 시간(ms).
  final int defaultIntervalMs;

  /// 이 값을 넘는 수신 간격은 보간하지 않고 즉시 이동한다(ms).
  ///
  /// 통신이 끊겼다 복구되면 간격이 수십 초로 벌어질 수 있는데, 그 간격 그대로 보간하면 마커가 아주 느리게
  /// 기어가 "멈춘 것"과 구별되지 않는다. 정상 전송 주기(2초)의 5배를 상한으로 잡아, 정상 지연 변동은
  /// 그대로 보간하고 통신 두절만 걸러낸다.
  final int maxIntervalMs;

  final Map<String, _Motion> _byId = {};
  final Set<String> _movedLastFrame = {};

  /// [id] 마커가 새 좌표를 받았다.
  void onCoordinateReceived(String id, LatLng target, DateTime now) {
    final motion = _byId.putIfAbsent(id, _Motion.new);
    final previousReceivedAt = motion.lastReceivedAt;
    motion.lastReceivedAt = now;

    final current = _positionOf(motion, now);
    // 첫 좌표(보간할 시작점이 없다)이거나 좌표가 그대로면 움직일 것이 없다 — 같은 자리에서 같은 자리로
    // "보간 중" 이 되면 정차지 마커까지 프레임마다 옮기게 된다.
    if (current == null || current == target) {
      motion
        ..start = target
        ..end = target
        ..startedAt = now
        ..durationMs = 0;
      return;
    }

    final intervalMs = previousReceivedAt == null
        ? defaultIntervalMs
        : now.difference(previousReceivedAt).inMilliseconds;

    // **이어붙이기** — 새 구간은 좌표가 실제로 향했던 지점(target)이 아니라 "지금 화면에 보이는 위치"에서
    // 시작한다. 그래야 새 좌표가 도착한 순간 마커가 이전 목표로 순간이동했다가 다시 출발하지 않는다.
    // 상한을 넘으면 durationMs 를 0 으로 둔다 — [_positionOf] 가 durationMs<=0 이면
    // 곧바로 end 를 돌려줘 "보간 없이 즉시 이동"과 같다.
    motion
      ..start = current
      ..end = target
      ..startedAt = now
      ..durationMs = intervalMs > maxIntervalMs ? 0 : intervalMs;
  }

  /// [now] 시점 [id] 마커의 보간된 위치. 좌표를 아직 한 번도 받지 못했으면 `null`.
  LatLng? positionAt(String id, DateTime now) {
    final motion = _byId[id];
    return motion == null ? null : _positionOf(motion, now);
  }

  /// 보간 중인 마커가 하나라도 있는가 — 어댑터가 프레임 틱을 켜 둘지 판단한다.
  bool isAnimating(DateTime now) =>
      _byId.values.any((m) => _isAnimating(m, now));

  /// 이번 프레임에 실제로 `setPosition` 을 부를 마커 id.
  ///
  /// 프레임(60Hz)마다 모든 마커에 네이티브 호출을 하면 정차지처럼 움직이지 않는 마커까지 초당 수십 번
  /// 호출돼 배터리·발열만 쓴다. 그래서 보간 중인 마커만 고른다. 보간이 끝난 **첫 프레임**은 마지막 자리에
  /// 정확히 놓으려고 한 번 더 고르고, 그다음부터는 고르지 않는다.
  List<String> idsToMove(DateTime now) {
    final ids = <String>[];
    final animatingNow = <String>{};
    for (final entry in _byId.entries) {
      final animating = _isAnimating(entry.value, now);
      if (animating) animatingNow.add(entry.key);
      if (animating || _movedLastFrame.contains(entry.key)) ids.add(entry.key);
    }
    _movedLastFrame
      ..clear()
      ..addAll(animatingNow);
    return ids;
  }

  /// 지도에서 사라진 마커의 상태를 버린다.
  void remove(String id) {
    _byId.remove(id);
    _movedLastFrame.remove(id);
  }

  LatLng? _positionOf(_Motion motion, DateTime now) {
    final start = motion.start;
    final end = motion.end;
    final startedAt = motion.startedAt;
    if (start == null || end == null || startedAt == null) return null;
    if (motion.durationMs <= 0) return end;

    // 진행률은 0~1 로 자른다 — 다음 좌표 도착이 늦어져 경과 시간이 보간 시간을 넘어도 마커가 목표 지점을
    // 지나쳐 계속 나아가지 않는다.
    final progress =
        (now.difference(startedAt).inMilliseconds / motion.durationMs).clamp(
          0.0,
          1.0,
        );
    return (
      lat: start.lat + (end.lat - start.lat) * progress,
      lng: start.lng + (end.lng - start.lng) * progress,
    );
  }

  bool _isAnimating(_Motion motion, DateTime now) {
    final startedAt = motion.startedAt;
    if (motion.start == null || motion.end == null || startedAt == null) {
      return false;
    }
    if (motion.durationMs <= 0) return false;
    return now.difference(startedAt).inMilliseconds < motion.durationMs;
  }
}

/// 마커 하나의 보간 상태.
class _Motion {
  LatLng? start;
  LatLng? end;
  DateTime? startedAt;
  int durationMs = 0;
  DateTime? lastReceivedAt;
}
