/// 지도 SDK 포트 — 화면 코드가 지켜야 할 유일한 규칙은 이 파일만 import 하는
/// 것이다(F4-B 1단계 공통 규칙 §2). `NaverMap` · `NMarker` · `NLatLng` 같은
/// SDK 타입은 `naver/naver_map_adapter.dart` 뒤에 숨는다 — 지도 SDK 를
/// 교체해도 화면은 이 파일의 타입만 알면 된다.
library;

import 'package:flutter/widgets.dart';
import 'package:manager_app/core/map/naver/naver_map_adapter.dart';

/// 지도 카메라(중심 좌표·확대 수준).
class MapCamera {
  const MapCamera({required this.lat, required this.lng, required this.zoom});

  final double lat;
  final double lng;
  final double zoom;
}

/// 마커의 종류 — 아이콘·색상 등 실제 표현은 어댑터가 정한다. 화면은 어떤
/// 대상을 찍는지만 밝힌다.
enum MapMarkerKind {
  /// 운행 중인 버스의 현재 위치.
  bus,

  /// 승하차지(정류장).
  stop,

  /// 학생의 위치(승하차 지점과 별도로 찍어야 할 때).
  student,
}

/// 지도 위에 놓일 마커 하나.
class MapMarker {
  const MapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    required this.kind,
  });

  final String id;
  final double lat;
  final double lng;
  final MapMarkerKind kind;
}

/// 지도 준비 완료 콜백 — SDK 가 타일을 그릴 준비를 마치면 호출된다.
typedef MapReadyCallback = void Function();

/// 지도 인증 실패 콜백. SDK 예외를 그대로 넘기되(예외 자체를 삼키거나
/// 다른 값으로 바꾸지 않는다), 화면 코드가 SDK 예외 타입을 몰라도 되도록
/// [Object] 로 받는다.
typedef MapAuthFailedCallback = void Function(Object exception);

/// 화면이 지도 SDK 를 직접 알지 못하게 감싸는 위젯.
///
/// 실제 렌더링·마커 배치는 [NaverMapAdapter] 가 맡는다. 이 클래스는 그
/// 어댑터를 감싸는 얇은 위임일 뿐이며, SDK import 는 이 파일에 없다.
class MapSurface extends StatelessWidget {
  const MapSurface({
    required this.camera,
    super.key,
    this.markers = const [],
    this.onReady,
    this.onAuthFailed,
  });

  /// 초기 카메라 위치. 마커 목록이 바뀌어도 카메라를 자동으로 다시
  /// 맞추지 않는다 — 필요하면 호출부가 새 [MapCamera] 를 내려준다.
  final MapCamera camera;

  /// 지도 위에 찍을 마커 목록.
  final List<MapMarker> markers;

  /// 지도 준비 완료 콜백.
  final MapReadyCallback? onReady;

  /// 인증 실패 콜백.
  final MapAuthFailedCallback? onAuthFailed;

  @override
  Widget build(BuildContext context) {
    return NaverMapAdapter(
      camera: camera,
      markers: markers,
      onReady: onReady,
      onAuthFailed: onAuthFailed,
    );
  }
}
