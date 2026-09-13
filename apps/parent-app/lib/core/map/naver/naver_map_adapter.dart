import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/map/naver/naver_map_init.dart';

/// `MapSurface` 계약을 실제 네이버 지도 SDK 로 구현하는 어댑터.
///
/// **이 파일과 이 폴더 바깥 어디에도 `package:flutter_naver_map` 을
/// import 하지 않는다** — 화면은 반드시 `map_surface.dart` 만 보고,
/// 여기가 SDK 타입(`NaverMap`·`NMarker`·`NLatLng`)이 나타나는 유일한
/// 자리다. 이 경계는 `test/architecture/map_port_boundary_test.dart` 가
/// 자동으로 강제한다.
class NaverMapAdapter extends StatefulWidget {
  const NaverMapAdapter({
    required this.camera,
    super.key,
    this.markers = const [],
    this.onReady,
    this.onAuthFailed,
  });

  final MapCamera camera;
  final List<MapMarker> markers;
  final VoidCallback? onReady;
  final void Function(Object exception)? onAuthFailed;

  @override
  State<NaverMapAdapter> createState() => _NaverMapAdapterState();
}

class _NaverMapAdapterState extends State<NaverMapAdapter> {
  // `probe_map_main.dart` 와 같은 방식 — 런타임에 `--dart-define` 으로
  // 주입한다. 실제 키 값은 이 파일을 포함해 어디에도 커밋하지 않는다.
  static const _clientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  late final Future<void> _initFuture;
  StreamSubscription<Object>? _authFailedSub;
  NaverMapController? _controller;
  final Map<String, NMarker> _markersById = {};

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
      unawaited(_syncMarkers(controller));
      if (!_sameCamera(oldWidget.camera, widget.camera)) {
        unawaited(
          controller.updateCamera(
            NCameraUpdate.scrollAndZoomTo(
              target: NLatLng(widget.camera.lat, widget.camera.lng),
              zoom: widget.camera.zoom,
            ),
          ),
        );
      }
    }
  }

  bool _sameCamera(MapCamera a, MapCamera b) =>
      a.lat == b.lat && a.lng == b.lng && a.zoom == b.zoom;

  @override
  void dispose() {
    unawaited(_authFailedSub?.cancel());
    super.dispose();
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

        return NaverMap(
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: NLatLng(widget.camera.lat, widget.camera.lng),
              zoom: widget.camera.zoom,
            ),
          ),
          onMapReady: (controller) {
            _controller = controller;
            unawaited(_syncMarkers(controller));
            widget.onReady?.call();
          },
        );
      },
    );
  }

  /// 마커 목록을 이전 상태와 비교해 추가·갱신·삭제만 반영한다 — 매번
  /// `clearOverlays` 로 통째로 다시 그리면 깜빡임이 생긴다.
  Future<void> _syncMarkers(NaverMapController controller) async {
    final incoming = {for (final m in widget.markers) m.id: m};

    final toRemove = _markersById.keys
        .where((id) => !incoming.containsKey(id))
        .toList();
    for (final id in toRemove) {
      final marker = _markersById.remove(id);
      if (marker != null) {
        await controller.deleteOverlay(marker.info);
      }
    }

    final toAdd = <NMarker>{};
    for (final entry in incoming.entries) {
      final existing = _markersById[entry.key];
      final target = NLatLng(entry.value.lat, entry.value.lng);
      if (existing == null) {
        // 아이콘 이미지·색상 커스터마이즈는 이번 라운드 범위 밖이다(성능·
        // 표현 튜닝은 2단계) — 종류 구분은 캡션 텍스트로만 한다.
        final marker = NMarker(
          id: entry.key,
          position: target,
          caption: NOverlayCaption(text: _captionFor(entry.value.kind)),
        );
        _markersById[entry.key] = marker;
        toAdd.add(marker);
      } else {
        existing.setPosition(target);
      }
    }
    if (toAdd.isNotEmpty) {
      await controller.addOverlayAll(toAdd);
    }
  }

  String _captionFor(MapMarkerKind kind) => switch (kind) {
        MapMarkerKind.bus => '버스',
        MapMarkerKind.stop => '승하차지',
        MapMarkerKind.student => '학생',
      };
}
