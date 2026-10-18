import 'dart:async';

import 'package:baraeda_app/map/map_surface.dart';
import 'package:baraeda_app/map/marker_motion_controller.dart';
import 'package:baraeda_app/map/naver/naver_map_init.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// `MapSurface` 계약을 실제 네이버 지도 SDK 로 구현하는 어댑터 — 두 앱이 같은 코드를 쓴다.
///
/// **이 폴더(`lib/map/naver/`) 바깥 어디에도 `package:flutter_naver_map` 을 import 하지
/// 않는다** — 화면은
/// `map_surface.dart` 만 보고, 여기가 SDK 타입(`NaverMap` · `NMarker` · `NLatLng`)이
/// 나타나는 유일한 자리다.
/// 이 경계는 `test/map/map_sdk_boundary_test.dart` 가 두 앱과 공용 패키지 전체에 대해 강제한다.
///
/// 앱마다 다른 것(마커 아이콘 · 선 색 · 이동 방식 · 맞춤 방식)은 [MapSurfaceOptions] 로 받는다.
class NaverMapAdapter extends StatefulWidget {
  const new({
    required this.camera,
    this.markers = const [],
    this.polylines = const [],
    this.fitToContent = false,
    this.fitPadding = const EdgeInsets.all(48),
    this.options = const MapSurfaceOptions(),
    super.key,
    this.onReady,
    this.onAuthFailed,
    this.onUserGesture,
  });

  final MapCamera camera;
  final List<MapMarker> markers;
  final List<MapPolyline> polylines;
  final bool fitToContent;
  final EdgeInsets fitPadding;
  final MapSurfaceOptions options;
  final MapReadyCallback? onReady;
  final MapAuthFailedCallback? onAuthFailed;
  final VoidCallback? onUserGesture;

  @override
  State<NaverMapAdapter> createState() => _NaverMapAdapterState();
}

class _NaverMapAdapterState extends State<NaverMapAdapter>
    with SingleTickerProviderStateMixin {
  /// 카메라가 새 좌표로 옮겨 가는 시간 — 마커 보간 간격(위치 송신 주기 약 2초)보다 살짝 짧게 둬 다음 좌표 전에 끝낸다.
  static const _cameraFollowDuration = Duration(milliseconds: 1800);

  /// 아이콘이 없는 승하차지 핀의 색 — 디자인 시스템의 `statusMoving`(앰버)과 같은 계열로, 버스 핀(기본 초록)과 갈린다.
  /// 지도 어댑터는 `BuildContext` 없이 마커를 만들어 토큰을 직접 읽지 못해 값을 한 곳에 둔다.
  static const _stopMarkerTint = Color(0xFFE08A00);

  /// 빌드 · 실행 시점에 `--dart-define=NAVER_MAP_CLIENT_ID=<값>` 으로 주입한다. 실제 키 값은 어디에도
  /// 커밋하지 않는다.
  static const _clientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  late final Future<void> _initFuture;
  StreamSubscription<Object>? _authFailedSub;
  NaverMapController? _controller;

  /// 오버레이 동기화를 한 번에 하나만 — 겹치면 핀 이미지가 빈 파일로 저장돼 iOS 에서 앱이 종료된다([SerialSync]).
  late final SerialSync _sync = SerialSync(() async {
    final controller = _controller;
    if (controller != null && mounted) await _syncOverlays(controller);
  });

  /// 지금 지도 위에 올라가 있는 마커(id 별) — 좌표가 바뀐 것만 옮기고 없어진 것은 지운다.
  final Map<String, NMarker> _markersById = {};

  /// 올라가 있는 마커의 모양 키(id 별) — 번호 · 내 승하차지 · 미경유가 바뀌면 아이콘을 다시 만든다.
  final Map<String, String> _looksById = {};

  /// 지금 지도 위에 올라가 있는 선의 모양 키(id 별) — 바뀌면 지우고 다시 그린다.
  final Map<String, String> _linesById = {};

  /// 마지막으로 카메라를 맞출 때의 대상 서명 — 이 값이 바뀔 때만 다시 맞춘다.
  String? _fittedSignature;

  /// 마커 id 별 보간 상태 — 계산 자체는 `MarkerMotionController`(순수)에 맡기고, 이 클래스는 "언제 부를지"만
  /// 담당한다.
  /// `MapSurfaceOptions.smoothMarkerMotion` 이 켜졌을 때만 쓴다.
  final MarkerMotionController _motion = MarkerMotionController();

  /// 화면 프레임마다 도는 틱 — 보간 중인 마커가 하나라도 있을 때만 켠다(프레임마다 `setPosition` 을 부르는
  /// 비용은 실제로 움직이는 마커가 있을 때만 낸다). 앱이 백그라운드(paused)면 프레임이 없어 네이티브 호출도 0이다.
  late final Ticker _ticker = createTicker(
    (_) => (_debugTick ?? _onFrameTick)(),
  );

  /// 시험이 틱 콜백을 바꿔 끼우는 자리 — [debugStartTickerForTest] 만 쓴다.
  VoidCallback? _debugTick;

  @override
  void initState() {
    super.initState();
    _initFuture = NaverMapInit.ensureInitialized(
      clientId: _clientId.isEmpty ? null : _clientId,
    );
    _authFailedSub = NaverMapInit.onAuthFailed.listen((ex) {
      widget.onAuthFailed?.call(ex);
    });
  }

  @override
  void didUpdateWidget(covariant NaverMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;
    unawaited(_sync.request());
    if (widget.options.followCameraChanges &&
        !_sameCamera(oldWidget.camera, widget.camera)) {
      // 마커는 새 좌표까지 약 2초에 걸쳐 미끄러진다 — 카메라가 즉시 옮겨 가면 마커가 매번 중앙에서 튕겨 나갔다
      // 돌아오므로, 같은 속도로 따라가게 천천히 옮긴다.
      final update =
          NCameraUpdate.scrollAndZoomTo(
            target: NLatLng(widget.camera.lat, widget.camera.lng),
            zoom: widget.camera.zoom,
          )..setAnimation(
            animation: NCameraAnimation.linear,
            duration: _cameraFollowDuration,
          );
      unawaited(controller.updateCamera(update));
    }
  }

  bool _sameCamera(MapCamera a, MapCamera b) =>
      a.lat == b.lat && a.lng == b.lng && a.zoom == b.zoom;

  @override
  void dispose() {
    // ⚠ 반드시 해제한다 — 안 하면 화면을 벗어난 뒤에도 프레임마다 `setPosition` 을 계속 부르는 누수가 된다
    // (`naver_map_adapter_dispose_test.dart` 가 이 규칙을 고정한다).
    _ticker.dispose();
    unawaited(_authFailedSub?.cancel());
    super.dispose();
  }

  /// 위젯 시험 전용 훅 — 실제 컨트롤러는 SDK 의 `onMapReady` 로만 오는데 위젯 시험에는 그 경로가 없다.
  /// 가짜 컨트롤러를 끼워 넣어 오버레이 동기화가 겹쳐 도는지 본다(`naver_map_adapter_sync_test.dart` 전용).
  @visibleForTesting
  // 시험 전용 메서드라 setter 로 바꾸지 않는다(getter 가 없어 다른 지적이 난다).
  // ignore: use_setters_to_change_properties
  void debugAttachControllerForTest(NaverMapController controller) {
    _controller = controller;
  }

  /// 위젯 시험 전용 훅 — 실제 SDK 의 `onMapReady` 는 위젯 시험 환경(플랫폼 채널 부재)에서 오지 않아 `_ticker`
  /// 가
  /// 정상 경로(`_syncOverlays` → `_syncTicker`)로 시작될 수 없다. `dispose()` 가 이 타이머를 멈추는
  /// 배선을 검사하려면
  /// 먼저 돌고 있는 상태를 만들어야 하는데, 시작 경로 자체는 이 검사의 대상이 아니므로(대상은 `dispose()`)
  /// 같은 `_ticker` 인스턴스를 직접 돌리는 것으로 대신한다(`naver_map_adapter_dispose_test.dart`
  /// 전용).
  @visibleForTesting
  void debugStartTickerForTest(VoidCallback onTick) {
    _debugTick = onTick;
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        // 초기화 중이거나 끝내 실패한 경우 앱이 정한 자리(기본은 회색)만 채운다 — `NaverMap` 위젯은 `build()`
        // 진입 시
        // `FlutterNaverMap.isInitialized` 를 단언(assert)하므로, 초기화가 끝나지 않은 채로 만들면
        // 위젯 시험 환경
        // (플랫폼 채널 부재)에서 그 단언이 곧바로 실패한다. "인증 실패"(`onAuthFailed`)와는 다른 경로라 그 콜백을
        // 여기서 대신 부르지 않는다.
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          final placeholder = widget.options.placeholderBuilder;
          return placeholder == null
              ? const ColoredBox(color: Color(0xFFE0E0E0))
              : placeholder(context, snapshot.error);
        }

        // 스크롤 뷰 안에서도 끌기 · 확대가 지도에 먼저 닿게 한다 — 기본값 false 면 페이지 스크롤이 제스처를 가져가
        // 지도가 움직이지 않는다(test/map/map_gesture_test.dart).
        return NaverMap(
          forceGesture: true,
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: NLatLng(widget.camera.lat, widget.camera.lng),
              zoom: widget.camera.zoom,
            ),
          ),
          onMapReady: (controller) {
            _controller = controller;
            unawaited(_sync.request());
            widget.onReady?.call();
          },
          // 코드가 옮긴 카메라(`developer`)와 사용자가 옮긴 카메라를 가른다 — 따라가기를 끄는 근거다.
          onCameraChange: (reason, animated) {
            if (reason == NCameraUpdateReason.gesture ||
                reason == NCameraUpdateReason.control) {
              widget.onUserGesture?.call();
            }
          },
        );
      },
    );
  }

  /// 마커 · 선을 이전 상태와 비교해 추가 · 갱신 · 삭제만 반영한다 — 매번 `clearOverlays` 로 통째로 다시 그리면
  /// 깜빡임이 생긴다.
  ///
  /// 보간이 켜져 있으면 기존 마커의 좌표는 여기서 대입하지 않는다 — 새 목표 좌표를 `MarkerMotionController` 에
  /// 알리기만 하고, 실제 `setPosition` 은 `_onFrameTick` 이 프레임마다 그 컨트롤러가 계산한 중간 지점으로
  /// 부른다.
  Future<void> _syncOverlays(NaverMapController controller) async {
    final smooth = widget.options.smoothMarkerMotion;
    final incoming = {for (final m in widget.markers) m.id: m};

    // 없어졌거나 모양이 달라진 마커를 지운다 — 모양이 달라진 것은 아래에서 새로 만들어 올린다.
    final toRemove = _markersById.keys
        .where(
          (id) =>
              !incoming.containsKey(id) ||
              incoming[id]!.lookKey != _looksById[id],
        )
        .toList();
    for (final id in toRemove) {
      final marker = _markersById.remove(id);
      _looksById.remove(id);
      _motion.remove(id);
      if (marker != null) await controller.deleteOverlay(marker.info);
    }

    final now = DateTime.now();
    final toAdd = <NAddableOverlay>{};
    for (final entry in incoming.entries) {
      final existing = _markersById[entry.key];
      final target = (lat: entry.value.lat, lng: entry.value.lng);
      if (smooth) _motion.onCoordinateReceived(entry.key, target, now);

      if (existing == null) {
        // 아이콘을 굳히는 사이 화면이 닫힐 수 있다 — 닫힌 뒤의 context 는 쓰지 않는다.
        if (!mounted) return;
        final marker = await _toNMarker(entry.value);
        _markersById[entry.key] = marker;
        _looksById[entry.key] = entry.value.lookKey;
        toAdd.add(marker);
      } else if (!smooth) {
        existing.setPosition(NLatLng(target.lat, target.lng));
      }
      // 보간이 켜진 기존 마커는 `_onFrameTick` 이 보간해 가며 옮긴다 — 여기서 `setPosition` 을 바로 부르면
      // 이어붙이기 없이 순간이동한다.
    }
    await _syncPolylines(controller, toAdd);
    if (!mounted) return;
    if (toAdd.isNotEmpty) await controller.addOverlayAll(toAdd);
    await _fitCameraIfNeeded(controller);

    if (smooth) _syncTicker(now);
  }

  /// 마커 한 개를 SDK 마커로 만든다. 앱이 아이콘을 주면 그 위젯을 이미지로 굳혀 쓰고, 없으면 기본 핀에 글자를 단다.
  Future<NMarker> _toNMarker(MapMarker marker) async {
    final position = NLatLng(marker.lat, marker.lng);
    final icon = widget.options.markerIcon?.call(marker);
    if (icon != null) {
      final image = await NOverlayImage.fromWidget(
        widget: icon.widget,
        size: icon.size,
        context: context,
      );
      return NMarker(
        id: marker.id,
        position: position,
        icon: image,
        // 동그라미 · 칩은 기준점이 가운데다 — 핀 끝이 좌표에 오는 물방울과 다르다.
        anchor: icon.centered ? NPoint.relativeCenter : NMarker.defaultAnchor,
        // 아이콘이 종류를 말하므로 글자는 이름표가 있을 때만 붙인다.
        caption: marker.label == null
            ? null
            : NOverlayCaption(text: marker.label!),
        // 왼쪽이 먼저이고, 다른 오버레이와 겹치면 위 · 오른쪽 순으로 옮긴다.
        captionAligns: const [NAlign.left, NAlign.top, NAlign.right],
      );
    }
    return NMarker(
      id: marker.id,
      position: position,
      caption: NOverlayCaption(text: marker.label ?? _captionFor(marker.kind)),
      // 기본 핀이 전부 같은 초록이라 버스와 승하차지가 글자 없이는 안 갈렸다.
      // 생성할 때 한 번만 지정한다 — 만든 뒤 바꾸지 않아 네이티브 호출이 늘지 않는다.
      iconTintColor: marker.kind == MapMarkerKind.stop
          ? _stopMarkerTint
          : Colors.transparent,
    );
  }

  /// 선을 지도에 맞춘다 — 없어진 것은 지우고, 모양이 달라진 것은 지우고 다시 그리고, 새것은 더한다.
  /// 테두리 색이 있으면 선마다 아래에 테두리 선을 한 겹 더 깐다(지도 길 위에서도 선이 보이게). 화면은 선 1개만 안다.
  Future<void> _syncPolylines(
    NaverMapController controller,
    Set<NAddableOverlay> toAdd,
  ) async {
    final hasHalo = widget.options.polylineStyle.haloColor != null;
    final incoming = {for (final line in widget.polylines) line.id: line};
    for (final id in _linesById.keys.toList()) {
      if (incoming[id]?.lookKey == _linesById[id]) continue;
      _linesById.remove(id);
      if (hasHalo) await controller.deleteOverlay(_polylineInfo('$id#halo'));
      await controller.deleteOverlay(_polylineInfo(id));
    }
    for (final line in incoming.values) {
      if (_linesById.containsKey(line.id)) continue;
      _linesById[line.id] = line.lookKey;
      if (hasHalo) toAdd.add(_toNPolyline(line, halo: true));
      toAdd.add(_toNPolyline(line, halo: false));
    }
  }

  NOverlayInfo _polylineInfo(String id) =>
      NOverlayInfo(type: NOverlayType.polylineOverlay, id: id);

  /// 선 색은 앱이 정한다 — 테두리 선은 [MapPolylineStyle.haloColor] 가 있을 때만 깐다.
  NPolylineOverlay _toNPolyline(MapPolyline line, {required bool halo}) {
    final style = widget.options.polylineStyle;
    final mainColor = line.passed
        ? (style.passedColor ?? style.color)
        : style.color;
    return NPolylineOverlay(
      id: halo ? '${line.id}#halo' : line.id,
      coords: [for (final p in line.points) NLatLng(p.lat, p.lng)],
      color: halo ? style.haloColor! : mainColor,
      width: halo ? style.haloWidth : style.width,
      lineCap: NLineCap.round,
      lineJoin: NLineJoin.round,
      // 점선은 도로가 아니라 승하차지끼리 곧게 이은 선이다 — 테두리는 실선으로 둬 길 위에서 끊겨 보이지 않게 한다.
      pattern: line.dashed && !halo ? const [8, 8] : const [],
    );
  }

  /// [MapSurface.fitToContent] — 맞춤 대상(`cameraFit` 이 정한 마커 id · 선)이 바뀐 때만 다시
  /// 맞춘다.
  /// 대상은 노선이고, 버스를 넣는지는 [MapSurfaceOptions.fitBusMarginMeters] 가 정한다.
  Future<void> _fitCameraIfNeeded(NaverMapController controller) async {
    if (!widget.fitToContent) return;
    final fit = cameraFit(
      widget.markers,
      widget.polylines,
      busMarginMeters: widget.options.fitBusMarginMeters,
    );
    if (fit == null) return;
    if (fit.signature == _fittedSignature) return;
    _fittedSignature = fit.signature;
    final bounds = fit.bounds;
    if (bounds.isPoint) {
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(bounds.south, bounds.west),
          zoom: widget.camera.zoom,
        ),
      );
      return;
    }
    await controller.updateCamera(
      NCameraUpdate.fitBounds(
        NLatLngBounds(
          southWest: NLatLng(bounds.south, bounds.west),
          northEast: NLatLng(bounds.north, bounds.east),
        ),
        padding: widget.fitPadding,
      ),
    );
  }

  /// 보간 중인 마커가 하나라도 있으면 타이머를 돌리고, 없으면 멈춘다.
  void _syncTicker(DateTime now) {
    if (_motion.isAnimating(now)) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onFrameTick() {
    final now = DateTime.now();
    // 보간 중인(움직이는) 마커만 옮긴다 — 정차지 마커는 네이티브 호출 0.
    for (final id in _motion.idsToMove(now)) {
      final marker = _markersById[id];
      final position = _motion.positionAt(id, now);
      if (marker != null && position != null) {
        marker.setPosition(NLatLng(position.lat, position.lng));
      }
    }
    _syncTicker(now);
  }

  String _captionFor(MapMarkerKind kind) => switch (kind) {
    MapMarkerKind.bus => '버스',
    MapMarkerKind.stop => '승하차지',
    MapMarkerKind.student => '학생',
    MapMarkerKind.waypoint => '경유',
  };
}
