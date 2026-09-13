/// [MapSurface] 계약의 네이버 지도 구현체.
///
/// **이 파일과 이 디렉터리(`lib/core/map/naver/`) 밖으로 `flutter_naver_map`
/// SDK 타입(`NaverMap` · `NMarker` · `NLatLng` · `NCameraPosition` 등)이
/// 나가면 안 된다** — `route_map_screen.dart` 등 화면 코드는
/// `lib/core/map/map_surface.dart` 만 import 한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:manager_app/core/map/map_surface.dart';

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
    super.key,
    this.onReady,
    this.onAuthFailed,
  });

  final MapCamera camera;
  final List<MapMarker> markers;
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
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(widget.camera.lat, widget.camera.lng),
          zoom: widget.camera.zoom,
        ),
      ),
      onMapReady: (controller) async {
        if (widget.markers.isNotEmpty) {
          await controller.addOverlayAll(
            widget.markers.map(_toNMarker).toSet(),
          );
        }
        widget.onReady?.call();
      },
    );
  }

  NMarker _toNMarker(MapMarker marker) {
    return NMarker(
      id: marker.id,
      position: NLatLng(marker.lat, marker.lng),
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
    }
  }
}
