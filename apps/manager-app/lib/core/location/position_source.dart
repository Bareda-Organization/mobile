/// GPS 등 실제 위치 획득 소스 — LOC-01 이 요구하는 좌표 하나를 제공한다.
///
/// 이번 라운드는 지도 SDK·위치 플러그인을 도입하지 않는다(브리프 범위 밖 —
/// `drive_mode_screen.dart` 의 지도 자리 placeholder 와 같은 이유이고,
/// `pubspec.yaml` 에도 위치 플러그인이 없다). 그래서 이 인터페이스만 두고
/// 기본 구현([UnavailablePositionSource])은 항상 `null` 을 반환해 전송
/// 자체를 건너뛴다 — 좌표를 지어내 보내면 근접 알림(NTF-04) 판정이 실제
/// 위치와 어긋난다. 다음 라운드는 이 인터페이스를 실제 GPS 구현으로
/// 교체하기만 하면 전송 파이프라인(`position_policy.dart`·
/// `PositionRepository`)은 그대로 재사용된다.
// `di.dart` 의 Provider<PositionSource> 조립 지점과 맞추려 인터페이스로
// 둔다(CONVENTIONS_FLUTTER.md §2, DelayRepository 등 여러 메서드짜리와
// 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
// ignore: one_member_abstracts
abstract interface class PositionSource {
  /// 지금 시점의 좌표 스냅샷. 아직 값을 못 구했으면 `null`.
  PositionSample? sample();
}

/// [PositionSource] 가 돌려주는 좌표 스냅샷 — §4.12 요청 본문과 거의 1:1.
///
/// `recordedAt` 을 여기 담는 이유 — §4.12 는 이 값이 "단말 측정 시각"이지
/// 전송 시각이 아니라고 명시한다. 실제 GPS 구현(예: geolocator 의
/// `Position.timestamp`)은 좌표를 얻은 시점의 시각을 함께 주므로, 전송
/// 직전에 `clockProvider` 로 다시 "지금"을 물으면 그사이 지연(대기열
/// 등)만큼 실제 측정 시각과 어긋난다.
class PositionSample {
  const PositionSample({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.speed,
    this.heading,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? speed;
  final double? heading;
}

/// 실제 위치 플러그인이 연동되기 전까지 쓰는 기본 구현 — 항상 `null`.
class UnavailablePositionSource implements PositionSource {
  const UnavailablePositionSource();

  @override
  PositionSample? sample() => null;
}
