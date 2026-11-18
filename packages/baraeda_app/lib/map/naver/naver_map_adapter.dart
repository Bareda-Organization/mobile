import 'dart:async';

import 'package:baraeda_app/map/map_surface.dart';
import 'package:baraeda_app/map/naver/naver_camera_updates.dart';
import 'package:baraeda_app/map/naver/naver_map_init.dart';
import 'package:baraeda_app/map/naver/naver_marker_driver.dart';
import 'package:baraeda_app/map/naver/naver_overlay_factory.dart';
import 'package:baraeda_app/map/naver/naver_polyline_sync.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// `MapSurface` 계약을 실제 네이버 지도 SDK 로 구현하는 어댑터 — 두 앱이 같은 코드를 쓴다.
///
/// **이 폴더(`lib/map/naver/`) 바깥 어디에도 `package:flutter_naver_map` 을
/// import 하지 않는다** — 화면은 `map_surface.dart` 만 보고, 여기가 SDK
/// 타입(`NaverMap` · `NMarker` · `NLatLng`)이 나타나는 유일한 자리다. 이 경계는
/// `test/map/map_sdk_boundary_test.dart` 가 두 앱과 공용 패키지 전체에 대해
/// 강제한다.
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

  /// 지도 위에 올라가 있는 선 — 바뀐 것만 지우고 다시 그린다.
  final NaverPolylineSync _polylines = NaverPolylineSync();

  /// 마지막으로 카메라를 맞출 때의 대상 서명 — 이 값이 바뀔 때만 다시 맞춘다.
  String? _fittedSignature;

  /// 보간 중인 마커를 프레임마다 옮기는 틱 — 이 클래스는 "언제 동기화할지"만 정한다.
  late final NaverMarkerDriver _driver = NaverMarkerDriver(this, _markersById);

  NaverOverlayFactory get _overlays => NaverOverlayFactory(widget.options);

  @override
  void initState() {
    super.initState();
    _initFuture = NaverMapInit.ensureInitialized(
      clientId: _clientId.isEmpty ? null : _clientId,
    );
    // 초기화 예외도 화면의 지도 오류 콜백으로 알린다(앱이 켠 경우) — 인증 실패와 같은 안내를 띄우게 한다.
    if (widget.options.reportInitFailure) {
      unawaited(
        _initFuture.catchError((Object e) {
          if (mounted) widget.onAuthFailed?.call(e);
        }),
      );
    }
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
        !NaverCameraUpdates.sameCamera(oldWidget.camera, widget.camera)) {
      unawaited(
        controller.updateCamera(NaverCameraUpdates.follow(widget.camera)),
      );
    }
  }

  @override
  void dispose() {
    // ⚠ 반드시 해제한다 — 안 하면 화면을 벗어난 뒤에도 프레임마다 `setPosition` 을 계속 부르는 누수가 된다
    // (`naver_map_adapter_dispose_test.dart` 가 이 규칙을 고정한다).
    _driver.dispose();
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

  /// 위젯 시험 전용 훅 — 실제 SDK 의 `onMapReady` 는 위젯 시험 환경(플랫폼 채널 부재)에서 오지 않아 틱이
  /// 정상 경로(`_syncOverlays` → `syncTicker`)로 시작될 수 없다. `dispose()` 가 이 타이머를
  /// 멈추는 배선을 검사하려면 먼저 돌고 있는 상태를 만들어야 하는데, 시작 경로 자체는 이 검사의 대상이 아니므로(대상은
  /// `dispose()`) 같은 틱 인스턴스를 직접 돌리는 것으로
  /// 대신한다(`naver_map_adapter_dispose_test.dart` 전용).
  @visibleForTesting
  void debugStartTickerForTest(VoidCallback onTick) =>
      _driver.debugStart(onTick);

  void _handleMapReady(NaverMapController controller) {
    _controller = controller;
    unawaited(_sync.request());
    widget.onReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    return _NaverMapView(
      initFuture: _initFuture,
      camera: widget.camera,
      placeholderBuilder: widget.options.placeholderBuilder,
      onMapReady: _handleMapReady,
      onUserGesture: widget.onUserGesture,
    );
  }

  /// 마커 · 선을 이전 상태와 비교해 추가 · 갱신 · 삭제만 반영한다 — 매번 `clearOverlays` 로 통째로 다시 그리면
  /// 깜빡임이 생긴다.
  ///
  /// 보간이 켜져 있으면 기존 마커의 좌표는 여기서 대입하지 않는다 — 새 목표 좌표를 `MarkerMotionController` 에
  /// 알리기만 하고, 실제 `setPosition` 은 틱이 프레임마다 그 컨트롤러가 계산한 중간 지점으로
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
      _driver.motion.remove(id);
      if (marker != null) await controller.deleteOverlay(marker.info);
    }

    final now = DateTime.now();
    final toAdd = <NAddableOverlay>{};
    for (final entry in incoming.entries) {
      final existing = _markersById[entry.key];
      final target = (lat: entry.value.lat, lng: entry.value.lng);
      if (smooth) _driver.motion.onCoordinateReceived(entry.key, target, now);

      if (existing == null) {
        // 아이콘을 굳히는 사이 화면이 닫힐 수 있다 — 닫힌 뒤의 context 는 쓰지 않는다.
        if (!mounted) return;
        final marker = await _overlays.marker(entry.value, context);
        _markersById[entry.key] = marker;
        _looksById[entry.key] = entry.value.lookKey;
        toAdd.add(marker);
      } else if (!smooth) {
        existing.setPosition(NLatLng(target.lat, target.lng));
      }
      // 보간이 켜진 기존 마커는 틱이 보간해 가며 옮긴다 — 여기서 `setPosition` 을 바로 부르면
      // 이어붙이기 없이 순간이동한다.
    }
    await _polylines.sync(controller, widget.polylines, _overlays, toAdd);
    if (!mounted) return;
    if (toAdd.isNotEmpty) await controller.addOverlayAll(toAdd);
    await _fitCameraIfNeeded(controller);

    if (smooth) _driver.syncTicker(now);
  }

  /// [MapSurface.fitToContent] — 맞춤 대상(`cameraFit` 이 정한 마커 id · 선)이 바뀐 때만 다시
  /// 맞춘다. 대상은 노선이고, 버스를 넣는지는 [MapSurfaceOptions.fitBusMarginMeters] 가 정한다.
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
    await controller.updateCamera(
      NaverCameraUpdates.fit(
        fit,
        zoom: widget.camera.zoom,
        padding: widget.fitPadding,
      ),
    );
  }
}

/// 네이버 지도 위젯 — 초기화가 끝나기 전에는 자리 표시만 채운다.
class _NaverMapView extends StatelessWidget {
  const new({
    required this.initFuture,
    required this.camera,
    required this.placeholderBuilder,
    required this.onMapReady,
    required this.onUserGesture,
  });

  final Future<void> initFuture;
  final MapCamera camera;
  final MapPlaceholderBuilder? placeholderBuilder;
  final void Function(NaverMapController controller) onMapReady;
  final VoidCallback? onUserGesture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        // 초기화 중이거나 끝내 실패한 경우 앱이 정한 자리(기본은 회색)만 채운다 — `NaverMap` 위젯은 `build()`
        // 진입 시 `FlutterNaverMap.isInitialized` 를 단언(assert)하므로, 초기화가 끝나지 않은 채로
        // 만들면 위젯 시험 환경 (플랫폼 채널 부재)에서 그 단언이 곧바로 실패한다. "인증 실패"(`onAuthFailed`)와는
        // 다른 경로라 그 콜백을 여기서 대신 부르지 않는다.
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          final placeholder = placeholderBuilder;
          return placeholder == null
              ? const ColoredBox(color: BaraedaMapColors.mapPlaceholder)
              : placeholder(context, snapshot.error);
        }

        // 스크롤 뷰 안에서도 끌기 · 확대가 지도에 먼저 닿게 한다 — 기본값 false 면 페이지 스크롤이 제스처를 가져가
        // 지도가 움직이지 않는다(test/map/map_gesture_test.dart).
        return NaverMap(
          forceGesture: true,
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: NLatLng(camera.lat, camera.lng),
              zoom: camera.zoom,
            ),
          ),
          onMapReady: onMapReady,
          // 코드가 옮긴 카메라(`developer`)와 사용자가 옮긴 카메라를 가른다 — 따라가기를 끄는 근거다.
          onCameraChange: (reason, animated) {
            if (reason == NCameraUpdateReason.gesture ||
                reason == NCameraUpdateReason.control) {
              onUserGesture?.call();
            }
          },
        );
      },
    );
  }
}
