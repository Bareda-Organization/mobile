/// [MapSurface] 계약의 네이버 지도 구현체.
///
/// **이 파일과 이 디렉터리(`lib/core/map/naver/`) 밖으로 `flutter_naver_map`
/// SDK 타입(`NaverMap` · `NMarker` · `NLatLng` · `NCameraPosition` 등)이
/// 나가면 안 된다** — `route_map_screen.dart` 등 화면 코드는
/// `lib/core/map/map_surface.dart` 만 import 한다.
library;

import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/core/map/naver/stop_pin.dart';
import 'package:manager_app/core/map/naver/waypoint_chip.dart';

/// 빌드·실행 시점에 `--dart-define=NAVER_MAP_CLIENT_ID=<값>` 으로 주입한다.
/// 실제 클라이언트 ID 값은 어떤 파일에도 커밋하지 않는다(F4-B 공통 규칙).
const _naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

/// 이 앱 안에서 `FlutterNaverMap().init()` 을 이미 성공적으로 호출했는지.
/// SDK 자체도 `FlutterNaverMap.isInitialized` 를 갖고 있지만 그 필드는
/// `@internal`(패키지 밖에서 읽으면 린트 경고) 이라 이 어댑터가 자기 상태를
/// 직접 추적한다 — 이 파일이 `.init()` 을 부르는 유일한 자리이므로 값이
/// 어긋날 일이 없다.
bool _sdkInitialized = false;

/// [MapSurface] 의 네이버 지도 구현. SDK 초기화(`FlutterNaverMap().init`)를
/// 이 위젯이 처음 만들어질 때 지연 수행하고, 초기화가 끝난 뒤에만 실제
/// `NaverMap` 위젯을 그린다 — 초기화 중·실패 상태를 화면에 그대로 노출해
/// "데이터 없음"과 "지도 인증 실패"를 구분한다.
class NaverMapAdapter extends StatefulWidget {
  const NaverMapAdapter({
    required this.camera,
    required this.markers,
    this.polylines = const [],
    this.fitToContent = false,
    super.key,
    this.onReady,
    this.onAuthFailed,
  });

  final MapCamera camera;
  final List<MapMarker> markers;
  final List<MapPolyline> polylines;
  final bool fitToContent;
  final MapReadyCallback? onReady;
  final MapAuthFailedCallback? onAuthFailed;

  @override
  State<NaverMapAdapter> createState() => _NaverMapAdapterState();
}

class _NaverMapAdapterState extends State<NaverMapAdapter> {
  bool _initialized = _sdkInitialized;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    if (!_initialized) {
      unawaited(_initSdk());
    }
  }

  Future<void> _initSdk() async {
    try {
      await FlutterNaverMap().init(
        clientId: _naverMapClientId.isEmpty ? null : _naverMapClientId,
        onAuthFailed: (ex) => widget.onAuthFailed?.call(ex),
      );
      _sdkInitialized = true;
      if (mounted) setState(() => _initialized = true);
    } on Exception catch (e) {
      widget.onAuthFailed?.call(e);
      if (mounted) setState(() => _initError = e);
    }
  }

  /// 지도가 준비된 뒤에만 채워지는 컨트롤러 — 그 전에는 오버레이를 만질 수 없다.
  NaverMapController? _controller;

  /// 오버레이 동기화를 한 번에 하나만 — 겹치면 핀 이미지가 빈 파일로 저장돼 iOS 에서 앱이 종료된다([SerialSync]).
  late final SerialSync _sync = SerialSync(() async {
    final controller = _controller;
    if (controller != null && mounted) await _syncOverlays(controller);
  });

  /// 지금 지도 위에 올라가 있는 마커(id 별) — 좌표가 바뀐 것만 옮기고 없어진 것은 지우려고 든다.
  final Map<String, NMarker> _markersById = {};

  /// 올라가 있는 마커의 모양 키(id 별) — 번호·미경유가 바뀌면 아이콘을 다시 만든다. 미승차 반영으로 승하차지가
  /// 운행 중에 미경유가 되거나 경유 지점 배포로 번호가 밀려도 마커 id 는 그대로라, 좌표만 비교하면 옛 아이콘이 남는다.
  final Map<String, String> _looksById = {};

  /// 지금 지도 위에 올라가 있는 선의 점 수(id 별) — 바뀌면 지우고 다시 그린다.
  final Map<String, int> _polylinePointCounts = {};

  /// 마지막으로 카메라를 맞출 때 넣은 마커 id 목록 — 이 값이 바뀔 때만 다시 맞춘다.
  String? _fittedSignature;

  @override
  void didUpdateWidget(covariant NaverMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller != null) unawaited(_sync.request());
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Text('지도를 불러오지 못했습니다')),
      );
    }
    if (!_initialized) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 스크롤 뷰 안에서도 끌기·확대가 지도에 먼저 닿게 한다 — 기본값 false 면 페이지 스크롤이 제스처를 가져간다
    // (R41-CHK, test/core/map/map_gesture_test.dart).
    return NaverMap(
      forceGesture: true,
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(widget.camera.lat, widget.camera.lng),
          zoom: widget.camera.zoom,
        ),
      ),
      onMapReady: (controller) async {
        _controller = controller;
        await _sync.request();
        widget.onReady?.call();
      },
    );
  }

  /// 마커·선을 지도에 맞춘다 — 없어진 것은 지우고, 새것은 더하고, 좌표만 바뀐 마커는 옮긴다.
  Future<void> _syncOverlays(NaverMapController controller) async {
    final incoming = {for (final m in widget.markers) m.id: m};
    for (final id in _markersById.keys.toList()) {
      final stale = incoming[id]?.lookKey != _looksById[id];
      if (!stale) continue;
      _looksById.remove(id);
      await controller.deleteOverlay(_markersById.remove(id)!.info);
    }
    final overlays = <NAddableOverlay>{};
    for (final marker in widget.markers) {
      // 아이콘을 굳히는 사이 화면이 닫힐 수 있다 — 닫힌 뒤의 context 는 쓰지 않는다.
      if (!mounted) return;
      final existing = _markersById[marker.id];
      if (existing == null) {
        final created = await _toNMarker(marker);
        _markersById[marker.id] = created;
        _looksById[marker.id] = marker.lookKey;
        overlays.add(created);
      } else {
        existing.setPosition(NLatLng(marker.lat, marker.lng));
      }
    }
    final lineIds = {for (final line in widget.polylines) line.id};
    for (final id in _polylinePointCounts.keys.toList()) {
      if (lineIds.contains(id)) continue;
      _polylinePointCounts.remove(id);
      await controller.deleteOverlay(
        NOverlayInfo(type: NOverlayType.polylineOverlay, id: id),
      );
    }
    for (final line in widget.polylines) {
      if (_polylinePointCounts[line.id] == line.points.length) continue;
      if (_polylinePointCounts.containsKey(line.id)) {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.polylineOverlay, id: line.id),
        );
      }
      _polylinePointCounts[line.id] = line.points.length;
      overlays.add(_toNPolyline(line));
    }
    if (!mounted) return;
    if (overlays.isNotEmpty) await controller.addOverlayAll(overlays);
    await _fitCameraIfNeeded(controller);
  }

  /// [MapSurface.fitToContent] — 맞춤 대상(`cameraFit` 이 정한 마커 id)이 바뀐 때만 다시 맞춘다.
  /// 대상은 노선이고, 버스는 노선 근처일 때만 들어간다.
  Future<void> _fitCameraIfNeeded(NaverMapController controller) async {
    if (!widget.fitToContent) return;
    final fit = cameraFit(widget.markers, widget.polylines);
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
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  /// 도로 경로는 승하차지 핀(초록)과 구별되는 파란 선으로 그린다.
  NPolylineOverlay _toNPolyline(MapPolyline line) => NPolylineOverlay(
    id: line.id,
    coords: [for (final p in line.points) NLatLng(p.lat, p.lng)],
    color: const Color(0xFF2563EB),
    width: 5,
    lineCap: NLineCap.round,
    lineJoin: NLineJoin.round,
  );

  /// 정차지는 순번 핀 이미지를 아이콘으로 쓴다 — 기준점이 SDK 기본값(아래 가운데)이라 핀 끝이
  /// 좌표에 온다([StopPin] 문서). 핀과 숫자가 종류를 말하므로 "승하차지" 글자는 붙이지 않는다.
  Future<NMarker> _toNMarker(MapMarker marker) async {
    final position = NLatLng(marker.lat, marker.lng);
    if (marker.kind == MapMarkerKind.stop) {
      final icon = await NOverlayImage.fromWidget(
        widget: StopPin(seq: marker.seq, skipped: marker.skipped),
        size: StopPin.size,
        context: context,
      );
      return NMarker(id: marker.id, position: position, icon: icon);
    }
    if (marker.kind == MapMarkerKind.waypoint) {
      // 칩의 가운데가 좌표에 온다 — 핀과 달리 끝점이 없다.
      final icon = await NOverlayImage.fromWidget(
        widget: const WaypointChip(),
        size: WaypointChip.size,
        context: context,
      );
      return NMarker(
        id: marker.id,
        position: position,
        icon: icon,
        anchor: NPoint.relativeCenter,
      );
    }
    return NMarker(
      id: marker.id,
      position: position,
      caption: NOverlayCaption(text: _captionFor(marker.kind)),
    );
  }

  String _captionFor(MapMarkerKind kind) {
    switch (kind) {
      case MapMarkerKind.bus:
        return '버스';
      case MapMarkerKind.stop:
        return '승하차지';
      case MapMarkerKind.student:
        return '학생';
      case MapMarkerKind.waypoint:
        return '경유';
    }
  }
}
