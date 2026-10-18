/// 지도 화면 전체가 의존하는 유일한 공개 계약 — 두 앱(학부모 · 매니저)이 같은 지도 위젯을 쓴다.
///
/// 지도 공급자(네이버 · Tmap)는 가격 정책에 따라 바뀔 수 있다(`IMPLEMENTATION_PLAN.md §8.3.1`). 화면이
/// SDK 타입을 직접 참조하면 공급자를 바꿀 때 화면을 전부 고쳐야 하므로, SDK 타입은 `naver/` 폴더 밖에 한 줄도 나타나지
/// 않게 막는다(`map_sdk_boundary_test`). 이 파일은 `naver/naver_map_adapter.dart` 로 위임만
/// 한다.
///
/// 두 앱의 차이(번호 핀 · 경유 칩 · 선 색 · 부드러운 이동 · 맞춤 방식)는 코드 분기가 아니라 [MapSurfaceOptions]
/// 로 앱이 정한다.
library;

import 'package:baraeda_app/map/map_models.dart';
import 'package:baraeda_app/map/naver/naver_map_adapter.dart';
import 'package:flutter/material.dart';

export 'package:baraeda_app/map/map_fit.dart';
export 'package:baraeda_app/map/map_models.dart';

/// 마커 하나를 지도 아이콘으로 굳힐 위젯 — 어댑터가 이 위젯을 이미지로 만들어 마커 아이콘으로 쓴다.
class MapMarkerIcon {
  const new({required this.widget, required this.size, this.centered = false});

  final Widget widget;

  /// 이미지로 굳힐 크기 — 위젯 크기와 같게 둔다.
  final Size size;

  /// `true` 면 이미지 가운데가 좌표에 온다(동그라미 · 칩). `false` 면 SDK 기본값인 아래 가운데가 좌표에 온다(핀
  /// 끝).
  final bool centered;
}

/// 마커의 아이콘을 정하는 앱 쪽 함수. `null` 이면 SDK 기본 핀에 글자(`label` 또는 종류별 기본 글자)를 단다.
typedef MapMarkerIconBuilder = MapMarkerIcon? Function(MapMarker marker);

/// 지도 선의 색 — 앱마다 다르다.
class MapPolylineStyle {
  const new({
    required this.color,
    this.passedColor,
    this.haloColor,
    this.width = 5,
    this.haloWidth = 9,
  });

  /// 앞으로 갈 길의 색.
  final Color color;

  /// 지나온 길(`MapPolyline.passed`)의 색. `null` 이면 [color] 를 그대로 쓴다.
  final Color? passedColor;

  /// 선 아래에 한 겹 더 까는 테두리 색 — 지도 길 위에서도 선이 보이게 한다. `null` 이면 테두리가 없다.
  final Color? haloColor;

  final double width;
  final double haloWidth;
}

/// 지도 상태(초기화 중 · 실패) 자리에 그릴 위젯. [error] 가 `null` 이면 초기화 중이다.
typedef MapPlaceholderBuilder =
    Widget Function(BuildContext context, Object? error);

/// 앱 하나에서 모든 지도 화면이 같게 쓰는 설정 — 화면마다 다시 쓰지 않도록 앱이 상수 하나로 만든다.
class MapSurfaceOptions {
  const new({
    this.markerIcon,
    this.polylineStyle = const MapPolylineStyle(color: Color(0xFF2563EB)),
    this.fitBusMarginMeters,
    this.smoothMarkerMotion = false,
    this.followCameraChanges = false,
    this.placeholderBuilder,
    this.reportInitFailure = false,
  });

  /// 마커 아이콘 — 없으면 모든 마커가 SDK 기본 핀이다.
  final MapMarkerIconBuilder? markerIcon;

  final MapPolylineStyle polylineStyle;

  /// 카메라 맞춤에 버스를 넣는 거리(미터). `null` 이면 버스를 맞춤에서 뺀다 — 달리는 중에는 카메라가 버스를
  /// 따라가고, 맞춤은 버스가 없는 화면에서만 쓴다. 값이 있으면 노선 사각형을 이만큼 넓힌 범위 안의 버스만 넣는다.
  final double? fitBusMarginMeters;

  /// `true` 면 기존 마커가 새 좌표까지 수신 간격만큼 미끄러져 움직인다. `false` 면 좌표가 오는 즉시 옮긴다.
  final bool smoothMarkerMotion;

  /// `true` 면 `MapSurface.camera` 가 바뀔 때 카메라가 새 중심으로 따라간다. `false` 면 초기 위치로만
  /// 쓴다.
  final bool followCameraChanges;

  /// 초기화 중 · 실패 자리의 위젯. `null` 이면 회색 빈 자리다.
  final MapPlaceholderBuilder? placeholderBuilder;

  /// `true` 면 SDK 초기화 예외를 `MapSurface.onAuthFailed` 로도 알린다 —
  /// 화면이 "지도 인증 실패" 안내를 띄우게 한다. `false` 면 초기화 실패는
  /// [placeholderBuilder] 자리만 채운다.
  final bool reportInitFailure;
}

/// 화면이 실제로 그리는 지도 위젯 — 내부 구현은 전부 `naver/naver_map_adapter.dart` 에 있다.
class MapSurface extends StatelessWidget {
  const new({
    required this.camera,
    required this.options,
    super.key,
    this.markers = const [],
    this.polylines = const [],
    this.fitToContent = false,
    this.fitPadding = const EdgeInsets.all(48),
    this.onReady,
    this.onAuthFailed,
    this.onUserGesture,
  });

  /// 초기 카메라 위치. [MapSurfaceOptions.followCameraChanges] 가 꺼져 있으면 마커 목록이 바뀌어도
  /// 카메라를 자동으로 다시 맞추지 않는다 — 필요하면 호출부가 새 [MapCamera] 를 내려준다.
  final MapCamera camera;

  /// 지도 위에 찍을 마커 목록.
  final List<MapMarker> markers;

  /// 지도 위에 그릴 선 목록(도로 경로 등).
  final List<MapPolyline> polylines;

  /// `true` 면 카메라를 노선(승하차지 핀 · 선)이 전부 보이게 맞춘다 — 지도가 준비된 직후와 맞춤 대상이 바뀔 때만.
  /// 좌표만 바뀔 때는 맞추지 않는다(사용자가 옮겨 둔 화면을 빼앗지 않는다). 버스를 맞춤에 넣는지는
  /// [MapSurfaceOptions.fitBusMarginMeters] 가 정한다. [camera] 는 맞추기 전 초기 위치다.
  final bool fitToContent;

  /// [fitToContent] 로 맞출 때 노선 둘레에 비워 둘 여백 — 지도 위를 덮는 머리줄 · 아래 시트만큼 늘려 노선이 가려지지
  /// 않게 한다.
  final EdgeInsets fitPadding;

  /// 앱이 정한 설정(마커 아이콘 · 선 색 · 이동 방식 · 맞춤 방식).
  final MapSurfaceOptions options;

  /// 지도가 사용자 조작을 받을 수 있는 시점에 한 번 호출된다.
  final MapReadyCallback? onReady;

  /// SDK 인증 실패 시 호출된다. 원본 예외를 가공하지 않고 그대로 넘긴다(오류 분류는 호출부가 한다).
  final MapAuthFailedCallback? onAuthFailed;

  /// 사용자가 손으로 지도를 움직이거나 확대 · 축소했을 때 호출된다 — 코드가 카메라를 옮긴 경우는 부르지 않는다.
  final VoidCallback? onUserGesture;

  @override
  Widget build(BuildContext context) {
    return NaverMapAdapter(
      camera: camera,
      markers: markers,
      polylines: polylines,
      fitToContent: fitToContent,
      fitPadding: fitPadding,
      options: options,
      onReady: onReady,
      onAuthFailed: onAuthFailed,
      onUserGesture: onUserGesture,
    );
  }
}
