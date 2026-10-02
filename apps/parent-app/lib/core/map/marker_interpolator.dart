/// 위경도 두 점 사이를 진행률로 선형 보간하는 순수 계산 하나만 담는다.
///
/// **판단 근거 — 왜 이 파일을 어댑터 밖에 따로 두는가**: 이 앱의 위젯
/// 시험은 플랫폼 채널이 없어 지도 SDK 초기화를 검증하지 못한다
/// (`BRIEF-P2.md` 이월 6). 보간 로직이 SDK 어댑터 안에 섞여 있으면
/// 검사할 방법이 없어지므로, `DateTime`·`Timer` 같은 실행 환경 없이
/// 순수하게 계산만 하는 부분을 여기로 뺐다. 실제로 프레임마다 이
/// 계산을 부르는 것은 `naver/naver_map_adapter.dart` 의 몫이다.
library;

/// 위경도 좌표 하나. `MapMarker`(공개 계약)와 이름을 겹치지 않게
/// 짧은 record 타입으로 둔다 — 구조적 동등성이 자동으로 생겨 검사에서
/// `==` 비교가 그대로 통한다.
typedef LatLng = ({double lat, double lng});

class MarkerInterpolator {
  const new _();

  /// [progress] 가 0 이면 [start], 1 이면 [end], 그 사이는 선형 보간한
  /// 중간 지점이다. **0~1 범위를 벗어난 값은 잘라낸다** — 다음 좌표
  /// 도착이 늦어져 경과 시간이 보간 시간을 넘어도(진행률 1 초과) 마커가
  /// 목표 지점을 지나쳐 계속 나아가지 않게 막는 것이 이 함수의 핵심
  /// 책임이다.
  static LatLng at({
    required LatLng start,
    required LatLng end,
    required double progress,
  }) {
    final clamped = progress.clamp(0.0, 1.0);
    return (
      lat: start.lat + (end.lat - start.lat) * clamped,
      lng: start.lng + (end.lng - start.lng) * clamped,
    );
  }
}
