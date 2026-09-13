/// 지도 화면 전체가 의존해야 하는 **유일한 공개 계약**이다.
///
/// **판단 근거 — 왜 포트 뒤에 두는가**: 지도 공급자(네이버 vs Tmap)는
/// 가격 정책에 따라 나중에 바뀔 수 있다(`IMPLEMENTATION_PLAN.md §8.3.1`).
/// 화면 코드가 `NaverMap`·`NMarker`·`NLatLng` 같은 SDK 타입을 직접 참조하면
/// 공급자를 바꿀 때 화면 20여 개를 전부 고쳐야 한다 — 이 파일과
/// `naver/` 하위 파일만 바뀌면 되도록, SDK 타입은 이 파일 바깥(화면 쪽)에
/// **한 줄도** 나타나지 않게 막는다. 그 경계는
/// `test/architecture/map_port_boundary_test.dart` 가 자동으로 검사한다.
///
/// 이 파일 자체는 `naver/naver_map_adapter.dart` 를 참조하지만, 그 파일
/// 안에서만 `package:flutter_naver_map` 을 쓰므로 경계 규칙을 어기지
/// 않는다 — "화면은 이 파일만 보고, 이 파일이 어댑터로 위임한다"가
/// 포트/어댑터 구조의 본래 모양이다.
library;

import 'package:flutter/widgets.dart';
import 'package:parent_app/core/map/naver/naver_map_adapter.dart';

/// 카메라(지도가 비추는 중심·확대 수준). 좌표계는 위경도(WGS84)를 가정한다.
class MapCamera {
  const MapCamera({required this.lat, required this.lng, this.zoom = 15});

  final double lat;
  final double lng;
  final double zoom;
}

/// 마커 한 개가 무엇을 가리키는지 — 공급자를 바꿔도 이 3종 분류는 그대로
/// 간다(외양만 어댑터가 새로 그린다).
enum MapMarkerKind { bus, stop, student }

/// 지도 위에 찍을 점 하나. `id` 는 같은 마커를 다음 갱신에서도 알아보기
/// 위한 값이라 화면마다 고유해야 한다(예: `'bus-$studentId'`).
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

/// 화면이 실제로 그리는 지도 위젯. 내부 구현은 전부
/// `naver/naver_map_adapter.dart` 에 있다 — 이 클래스는 그 위임 하나만
/// 한다.
class MapSurface extends StatelessWidget {
  const MapSurface({
    required this.camera,
    super.key,
    this.markers = const [],
    this.onReady,
    this.onAuthFailed,
  });

  final MapCamera camera;
  final List<MapMarker> markers;

  /// 지도가 사용자 조작을 받을 수 있는 시점에 한 번 호출된다.
  final VoidCallback? onReady;

  /// SDK 인증 실패 시 호출된다. 원본 예외를 가공하지 않고 그대로 넘긴다
  /// (팀 공통 규칙 — 오류 분류는 호출부가 한다).
  final void Function(Object exception)? onAuthFailed;

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
