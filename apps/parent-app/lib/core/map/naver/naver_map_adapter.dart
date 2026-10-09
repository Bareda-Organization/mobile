import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:parent_app/core/map/frame_move_selector.dart';
import 'package:parent_app/core/map/frame_ticker.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/map/marker_motion_controller.dart';
import 'package:parent_app/core/map/naver/naver_map_init.dart';
import 'package:parent_app/core/map/naver/stop_number_pin.dart';

/// `MapSurface` 계약을 실제 네이버 지도 SDK 로 구현하는 어댑터.
///
/// **이 파일과 이 폴더 바깥 어디에도 `package:flutter_naver_map` 을
/// import 하지 않는다** — 화면은 반드시 `map_surface.dart` 만 보고,
/// 여기가 SDK 타입(`NaverMap`·`NMarker`·`NLatLng`)이 나타나는 유일한
/// 자리다. 이 경계는 `test/architecture/map_port_boundary_test.dart` 가
/// 자동으로 강제한다.
class NaverMapAdapter extends StatefulWidget {
  const new({
    required this.camera,
    super.key,
    this.markers = const [],
    this.polylines = const [],
    this.fitToContent = false,
    this.fitPadding = const EdgeInsets.all(48),
    this.onReady,
    this.onAuthFailed,
    this.onUserGesture,
  });

  final MapCamera camera;
  final List<MapMarker> markers;
  final List<MapPolyline> polylines;
  final bool fitToContent;
  final EdgeInsets fitPadding;
  final VoidCallback? onReady;
  final void Function(Object exception)? onAuthFailed;
  final VoidCallback? onUserGesture;

  @override
  State<NaverMapAdapter> createState() => _NaverMapAdapterState();
}

class _NaverMapAdapterState extends State<NaverMapAdapter> {
  /// 카메라가 새 좌표로 옮겨 가는 시간 — 마커 보간 간격(위치 송신 주기 약 2초)보다 살짝 짧게 둬 다음 좌표 전에 끝낸다.
  static const _cameraFollowDuration = Duration(milliseconds: 1800);

  /// 승하차지 핀 색 — 디자인 시스템의 `statusMoving`(앰버)과 같은 계열로, 버스 핀(기본 초록)과 갈린다.
  /// 지도 어댑터는 `BuildContext` 없이 마커를 만들어 토큰을 직접 읽지 못해 값을 한 곳에 둔다.
  static const _stopMarkerTint = Color(0xFFE08A00);

  // `probe_map_main.dart` 와 같은 방식 — 런타임에 `--dart-define` 으로
  // 주입한다. 실제 키 값은 이 파일을 포함해 어디에도 커밋하지 않는다.
  static const _clientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  late final Future<void> _initFuture;
  StreamSubscription<Object>? _authFailedSub;
  NaverMapController? _controller;

  /// 마커 동기화를 한 번에 하나만 — 겹치면 핀 이미지가 빈 파일로 저장돼 iOS 에서 앱이 종료된다([SerialSync]).
  late final SerialSync _sync = SerialSync(() async {
    final controller = _controller;
    if (controller != null && mounted) await _syncMarkers(controller);
  });
  final Map<String, NMarker> _markersById = {};

  /// 올라가 있는 마커의 모양 키(id 별) — 번호 · 지나감 · 내 승하차지가 바뀌면 아이콘을 다시 만든다.
  final Map<String, String> _looksById = {};

  /// 지금 지도 위에 올라가 있는 선의 모양 키(id 별) — 바뀌면 지우고 다시 그린다.
  final Map<String, String> _linesById = {};

  /// 마지막으로 카메라를 맞출 때의 대상 서명 — 이 값이 바뀔 때만 다시 맞춘다.
  String? _fittedSignature;

  /// 마커 id 별 보간 상태 — 계산 자체는 `MarkerMotionController`(순수)에
  /// 맡기고, 이 클래스는 "언제 부를지"만 담당한다.
  final Map<String, MarkerMotionController> _motionById = {};

  /// 보간 중인 마커가 하나라도 있을 때만 돈다 — 프레임마다 `setPosition`
  /// 을 부르는 비용은 실제로 움직이는 마커가 있을 때만 낸다.
  final FrameTicker _frameTicker = FrameTicker();

  /// 프레임마다 `setPosition` 을 부를 마커를 고른다.
  final FrameMoveSelector _moveSelector = FrameMoveSelector();

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
    if (controller != null) {
      unawaited(_sync.request());
      if (!_sameCamera(oldWidget.camera, widget.camera)) {
        // 마커는 새 좌표까지 약 2초에 걸쳐 미끄러진다 — 카메라가 즉시 옮겨 가면 마커가 매번 중앙에서 튕겨 나갔다
        // 돌아오므로, 같은 속도로 따라가게 천천히 옮긴다(R46 B2 #12).
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
  }

  bool _sameCamera(MapCamera a, MapCamera b) =>
      a.lat == b.lat && a.lng == b.lng && a.zoom == b.zoom;

  @override
  void dispose() {
    // ⚠ 반드시 멈춘다 — 안 멈추면 화면을 벗어난 뒤에도 프레임마다
    // `setPosition` 을 계속 부르는 누수가 된다(`test/core/map/
    // frame_ticker_test.dart` 가 이 규칙을 고정한다).
    _frameTicker.stop();
    unawaited(_authFailedSub?.cancel());
    super.dispose();
  }

  /// 위젯 시험 전용 훅 — 실제 컨트롤러는 SDK 의 `onMapReady` 로만 오는데 위젯 시험에는 그 경로가 없다.
  /// 가짜 컨트롤러를 끼워 넣어 마커 동기화가 겹쳐 도는지 본다
  /// (`test/core/map/naver/naver_map_adapter_sync_test.dart` 전용).
  @visibleForTesting
  // 시험 전용 메서드라 setter 로 바꾸지 않는다(getter 가 없어 다른 지적이 난다).
  // ignore: use_setters_to_change_properties
  void debugAttachControllerForTest(NaverMapController controller) {
    _controller = controller;
  }

  /// 위젯 시험 전용 훅 — 실제 SDK 의 `onMapReady` 는 위젯 시험 환경(플랫폼
  /// 채널 부재)에서 오지 않아 `_frameTicker` 가 정상 경로(`_syncMarkers` →
  /// `_syncFrameTicker`)로 시작될 수 없다. `dispose()` 가 이 타이머를
  /// 멈추는 배선을 검사하려면 먼저 돌고 있는 상태를 만들어야 하는데,
  /// 시작 경로 자체는 이 검사의 대상이 아니므로(대상은 `dispose()`)
  /// 같은 `_frameTicker` 인스턴스를 직접 돌리는 것으로 대신한다.
  /// (`test/core/map/naver/naver_map_adapter_dispose_test.dart` 전용)
  @visibleForTesting
  void debugStartFrameTickerForTest(VoidCallback onTick) {
    _frameTicker.start(onTick);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        // 로딩 중이거나(테스트 환경처럼) 초기화가 끝내 실패한 경우 둘 다
        // 회색 자리만 채운다 — `NaverMap` 위젯은 `build()` 진입 시
        // `FlutterNaverMap.isInitialized` 를 단언(assert)하므로, 초기화가
        // 끝나지 않은 채로 만들면 위젯 시험 환경(플랫폼 채널 부재)에서
        // 그 단언이 곧바로 실패한다. 이 화면 판단은 §1(보고서)에 남긴다 —
        // "인증 실패"(`onAuthFailed`)와는 다른 경로라 그 콜백을 여기서
        // 대신 부르지 않는다.
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return const ColoredBox(color: Color(0xFFE0E0E0));
        }

        // 스크롤 뷰(ListView) 안에서도 끌기·확대가 지도에 먼저 닿게 한다 — 기본값 false 면 스크롤이 제스처를 가져가
        // 지도가 움직이지 않는다(R41-CHK, test/architecture/map_gesture_test.dart).
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

  /// 마커·선 목록을 이전 상태와 비교해 추가·갱신·삭제만 반영한다 — 매번
  /// `clearOverlays` 로 통째로 다시 그리면 깜빡임이 생긴다.
  ///
  /// **보간은 여기서 즉시 좌표를 대입하지 않는다** — 새 목표 좌표를
  /// `MarkerMotionController` 에 알리기만 하고, 실제 `setPosition` 은
  /// `_onFrameTick` 이 프레임마다 그 컨트롤러가 계산한 중간 지점으로
  /// 부른다(`COMMON-B2.md §2`: "프레임 타이머로 직접 계산해 position 에
  /// 반복 대입한다" — 카메라 애니메이션이 아니라 마커를 직접 옮기는
  /// 것이므로 SDK 위젯 트리 갱신이 아니라 여기서 처리한다).
  Future<void> _syncMarkers(NaverMapController controller) async {
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
      _motionById.remove(id);
      if (marker != null) {
        await controller.deleteOverlay(marker.info);
      }
    }

    final now = DateTime.now();
    final toAdd = <NAddableOverlay>{};
    for (final entry in incoming.entries) {
      final existing = _markersById[entry.key];
      final target = (lat: entry.value.lat, lng: entry.value.lng);
      _motionById
          .putIfAbsent(entry.key, MarkerMotionController.new)
          .onCoordinateReceived(target, now);

      if (existing == null) {
        // 아이콘을 굳히는 사이 화면이 닫힐 수 있다 — 닫힌 뒤의 context 는 쓰지 않는다.
        if (!mounted) return;
        final marker = await _toNMarker(entry.value);
        _markersById[entry.key] = marker;
        _looksById[entry.key] = entry.value.lookKey;
        toAdd.add(marker);
      }
      // existing != null 인 경우는 `_onFrameTick` 이 보간해 가며 옮긴다 —
      // 여기서 `setPosition` 을 바로 부르면 이어붙이기 없이 순간이동한다.
    }
    await _syncPolylines(controller, toAdd);
    if (!mounted) return;
    if (toAdd.isNotEmpty) {
      await controller.addOverlayAll(toAdd);
    }
    await _fitCameraIfNeeded(controller);

    _syncFrameTicker(now);
  }

  /// 마커 한 개를 SDK 마커로 만든다. 번호가 있으면(`seq`) 번호 핀 이미지를, 없으면 기본 핀을 쓴다.
  Future<NMarker> _toNMarker(MapMarker marker) async {
    final position = NLatLng(marker.lat, marker.lng);
    final seq = marker.seq;
    if (seq != null) {
      // 동그라미 핀의 기준점은 가운데다 — 핀 끝이 좌표에 오는 물방울과 다르다. 번호 핀이 종류를 말하므로
      // 글자는 이름표(내 승하차지)가 있을 때만 붙인다.
      final icon = await NOverlayImage.fromWidget(
        widget: StopNumberPin(seq: seq, mine: marker.mine),
        size: StopNumberPin.sizeOf(mine: marker.mine),
        context: context,
      );
      return NMarker(
        id: marker.id,
        position: position,
        icon: icon,
        anchor: NPoint.relativeCenter,
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
      // 기본 핀이 전부 같은 초록이라 버스와 내 승하차지가 글자 없이는 안 갈렸다(R46 B2 #10).
      // 생성할 때 한 번만 지정한다 — 만든 뒤 바꾸지 않아 네이티브 호출이 늘지 않는다.
      iconTintColor: marker.kind == MapMarkerKind.stop
          ? _stopMarkerTint
          : Colors.transparent,
    );
  }

  /// 선을 지도에 맞춘다 — 없어진 것은 지우고, 모양이 달라진 것은 지우고 다시 그리고, 새것은 더한다.
  /// 선마다 아래에 흰 테두리 선을 한 겹 더 깐다(시안 — 지도 길 위에서도 선이 보이게). 화면은 선 1개만 안다.
  Future<void> _syncPolylines(
    NaverMapController controller,
    Set<NAddableOverlay> toAdd,
  ) async {
    final incoming = {for (final line in widget.polylines) line.id: line};
    for (final id in _linesById.keys.toList()) {
      if (incoming[id]?.lookKey == _linesById[id]) continue;
      _linesById.remove(id);
      await controller.deleteOverlay(_polylineInfo('$id#halo'));
      await controller.deleteOverlay(_polylineInfo(id));
    }
    for (final line in incoming.values) {
      if (_linesById.containsKey(line.id)) continue;
      _linesById[line.id] = line.lookKey;
      toAdd
        ..add(_toNPolyline(line, halo: true))
        ..add(_toNPolyline(line, halo: false));
    }
  }

  NOverlayInfo _polylineInfo(String id) =>
      NOverlayInfo(type: NOverlayType.polylineOverlay, id: id);

  /// 시안의 색 — 앞으로 갈 길은 초록(`#1F5C4D`), 지나온 길은 회색(`#8F9995`), 아래 테두리는 흰색.
  NPolylineOverlay _toNPolyline(MapPolyline line, {required bool halo}) =>
      NPolylineOverlay(
        id: halo ? '${line.id}#halo' : line.id,
        coords: [for (final p in line.points) NLatLng(p.lat, p.lng)],
        color: halo
            ? Colors.white
            : (line.passed ? const Color(0xFF8F9995) : const Color(0xFF1F5C4D)),
        width: halo ? 9 : 5,
        lineCap: NLineCap.round,
        lineJoin: NLineJoin.round,
        // 점선은 도로가 아니라 승하차지끼리 곧게 이은 선이다 — 테두리는 실선으로 둬 길 위에서 끊겨 보이지 않게 한다.
        pattern: line.dashed && !halo ? const [8, 8] : const [],
      );

  /// [MapSurface.fitToContent] — 맞출 대상(버스가 아닌 마커와 선)이 바뀐 때만 다시 맞춘다.
  Future<void> _fitCameraIfNeeded(NaverMapController controller) async {
    if (!widget.fitToContent) return;
    final bounds = contentBounds(widget.markers, widget.polylines);
    if (bounds == null) return;
    final signature = [
      for (final m in widget.markers)
        if (m.kind != MapMarkerKind.bus) m.id,
      for (final line in widget.polylines) line.lookKey,
    ].join(',');
    if (signature == _fittedSignature) return;
    _fittedSignature = signature;
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
  void _syncFrameTicker(DateTime now) {
    final anyAnimating = _motionById.values.any((m) => m.isAnimating(now));
    if (anyAnimating) {
      if (!_frameTicker.isRunning) {
        _frameTicker.start(_onFrameTick);
      }
    } else {
      _frameTicker.stop();
    }
  }

  void _onFrameTick() {
    final now = DateTime.now();
    // 보간 중인(움직이는) 마커만 옮긴다 — 정차지 마커는 네이티브 호출 0(R46 D #11).
    for (final id in _moveSelector.select(_motionById, now)) {
      final marker = _markersById[id];
      final position = _motionById[id]?.currentPositionAt(now);
      if (marker != null && position != null) {
        marker.setPosition(NLatLng(position.lat, position.lng));
      }
    }
    _syncFrameTicker(now);
  }

  String _captionFor(MapMarkerKind kind) => switch (kind) {
    MapMarkerKind.bus => '버스',
    MapMarkerKind.stop => '승하차지',
    MapMarkerKind.student => '학생',
  };
}
