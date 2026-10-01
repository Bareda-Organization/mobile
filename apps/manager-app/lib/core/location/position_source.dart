import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:manager_app/core/constants/position_constants.dart';

/// GPS 등 실제 위치 획득 소스 — LOC-01 이 요구하는 좌표 하나를 제공한다.
///
/// 기본 구현은 [GeolocatorPositionSource](`geolocator` 플러그인, `di.dart`
/// 조립 지점)다. 권한 거부·위치 서비스 꺼짐이면 [sample] 은 계속 `null` 이고
/// [availability] 로 그 이유를 구별한다 — 좌표를 지어내 보내면 근접
/// 알림(NTF-04) 판정이 실제 위치와 어긋나므로, 화면은 안내만 보여주고
/// 전송 자체를 건너뛴다(기존 자바독의 근거 그대로). 전송
/// 파이프라인(`position_transmitter.dart` 의 타이머·`PositionRepository`)은
/// 이 인터페이스만 보고 구현을 모른다.
// `di.dart` 의 Provider<PositionSource> 조립 지점과 맞추려 인터페이스로
// 둔다(CONVENTIONS_FLUTTER.md §2, DelayRepository 등 여러 메서드짜리와
// 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
abstract interface class PositionSource {
  /// 지금 시점의 좌표 스냅샷. 아직 값을 못 구했거나 [availability] 가
  /// `available` 이 아니면 `null`.
  PositionSample? sample();

  /// [sample] 이 `null` 인 이유 — 화면이 "아직 못 받았을 뿐"과 "권한·서비스
  /// 문제" 를 구별해 안내 문구를 낼 수 있게 한다(LOC-01 할 일 2).
  PositionAvailability get availability;

  /// 위치 스트림 구독을 시작한다(`Ruling 360`) — 운행 중인 기사 회차가 생기면
  /// 앱 전역 송신기(`position_transmitter.dart`)가 부른다(`canTransmitPosition`
  /// 게이트). 이미 시작됐으면 아무 것도 하지 않는다(멱등) — 재빌드가
  /// 중복 구독을 만들지 않는다.
  void start();

  /// 권한·위치 서비스 상태만 다시 확인해 [availability] 를 갱신한다 — 스트림(포그라운드 서비스 알림)은
  /// 켜지 않고 권한 창도 다시 띄우지 않는다. 운행 시작 전 화면이 설정을 바꾼 것을 알아채는 용도다(M2-02).
  Future<void> recheck();

  /// 위치 스트림 구독을 멈춘다 — 운행 종료·로그아웃 등 송신기가 멎을 때 부른다.
  /// [start] 로 켜진 Android 포그라운드 서비스 알림·iOS 백그라운드 갱신도
  /// 이 호출로 함께 멎는다. 이미 멈췄으면 아무 것도 하지 않는다(멱등).
  void stop();

  /// 지금 좌표를 한 번만 측정한다(`Ruling 360` 회귀 보완, BRIEF-BG2) —
  /// [start] 를 부르지 않으므로 Android 포그라운드 서비스 알림·iOS
  /// 백그라운드 갱신을 켜지 않는다. 비상 발신처럼 [sample] 이 `null`(스트림
  /// 미시작 — 동승자 단말, 또는 송신이 끊긴 기사 단말)일 때만 쓴다. [timeout]
  /// 안에 못 받거나 권한·서비스 문제면 `null`(좌표를 지어내지 않는다,
  /// [sample] 문서 참고). 결과는 [sample] 의 캐시에 남지 않는다 — 스트림
  /// 구독과 완전히 별개 경로다.
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  });
}

/// `Ruling 360` — 플랫폼별 위치 스트림 설정을 만드는 순수 함수. Android 는
/// 포그라운드 서비스 알림을 달아야 화면이 꺼지거나 뒤로 가도 위치 콜백이
/// 계속 온다([ForegroundNotificationConfig]). iOS 는
/// `AppleSettings.allowBackgroundLocationUpdates` 로 같은 것을 사용
/// 중(`WhenInUse`) 권한만으로 해낸다(`Always` 불필요 — Apple 은 이미 도는
/// 위치 갱신을 앱이 백그라운드로 가도 이어 준다, 파란 표시줄로 사용자에게
/// 알린다). 순수 함수로 뺀 이유는 시험이 [TargetPlatform] 값만 바꿔 가며
/// 두 분기를 각각 검사할 수 있게 하려는 것뿐 — 실제 배선은
/// `defaultTargetPlatform` 을 읽는 [GeolocatorPositionSource] 가 맡는다.
LocationSettings buildLocationSettings(TargetPlatform platform) {
  const accuracy = LocationAccuracy.high; // 기존 값 그대로 유지
  return switch (platform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: accuracy,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '운행 중',
        notificationText: '학부모에게 버스 위치를 보내고 있습니다',
        enableWakeLock: true,
      ),
    ),
    // allowBackgroundLocationUpdates·pauseLocationUpdatesAutomatically 는
    // AppleSettings 기본값이 이미 true/false 라 명시하지 않는다(lint
    // avoid_redundant_argument_values) — 값 자체는 `buildLocationSettings`
    // 시험(iOS 분기)이 지킨다.
    TargetPlatform.iOS => AppleSettings(
      accuracy: accuracy,
      showBackgroundLocationIndicator: true,
    ),
    _ => const LocationSettings(accuracy: accuracy),
  };
}

/// [PositionSource.sample] 이 `null` 인 이유.
enum PositionAvailability {
  /// 정상 — 권한·위치 서비스 모두 확인됨(아직 첫 좌표를 못 받았을 수는 있다).
  available,

  /// 위치 권한이 거부됨(iOS `NSLocationWhenInUseUsageDescription` ·
  /// Android `ACCESS_FINE_LOCATION` 거부).
  permissionDenied,

  /// 기기 위치 서비스 자체가 꺼짐.
  serviceDisabled,
}

/// [Position] → [PositionSample] 변환 — 스트림(`_onPosition`)과 1회 측정
/// ([GeolocatorPositionSource.sampleOnce])이 같은 함수를 쓴다(BRIEF-BG2,
/// 두 벌 두지 않는다).
PositionSample _toSample(Position position) => PositionSample(
  lat: position.latitude,
  lng: position.longitude,
  // §4.12 는 이 값이 단말 측정 시각이라고 규정한다 — 전송 직전에
  // clockProvider 로 "지금" 을 다시 물으면 안 된다(PositionSample 문서 참고).
  recordedAt: position.timestamp,
  // iOS 는 측정 불가일 때 속도·방향에 -1 을 준다 — §4.12 범위 밖이라 서버가
  // 거부하므로, 음수면 그 필드를 아예 빼고 보낸다(브리프 §5.8.1.2 마지막
  // 행 근거).
  speed: position.speed >= 0 ? position.speed : null,
  heading: position.heading >= 0 ? position.heading : null,
);

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

/// 위치 플러그인이 연동되기 전 자리표시로 쓰던 구현 — 항상 `null`
/// (이제 `di.dart` 는 [GeolocatorPositionSource] 를 쓴다, 시험용으로만 남긴다).
class UnavailablePositionSource implements PositionSource {
  const UnavailablePositionSource();

  @override
  PositionSample? sample() => null;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

/// `geolocator` 플러그인으로 실제 GPS 좌표를 낸다(LOC-01).
///
/// [sample] 은 동기라 플러그인 호출(비동기)을 매 호출마다 다시 묻지 않고
/// 캐시를 돌려준다. 생성 시점에는 권한·위치 서비스 확인만 한다 — 실제
/// [Geolocator.getPositionStream] 구독(Android 포그라운드 서비스 알림·
/// iOS 백그라운드 갱신이 여기서 켜진다)은 [start] 를 불러야 시작한다
/// (`Ruling 360` — 동승자 단말에서는 이 구독 자체가 시작되지 않아야
/// 한다, 생성자에서 자동 구독하면 역할과 무관하게 켜진다).
class GeolocatorPositionSource implements PositionSource {
  GeolocatorPositionSource() {
    _ready = _init();
  }

  /// 생성자의 초기화(권한·위치 서비스 확인)가 끝났는지 — 시험 전용
  /// (`await source.ready`). 운영 코드는 기다리지 않는다: 첫 좌표가 아직
  /// 없으면 `sample()` 이 `null` 을 돌려주는 것으로 충분하다.
  @visibleForTesting
  Future<void> get ready => _ready;
  late final Future<void> _ready;

  PositionSample? _lastSample;
  PositionAvailability _availability = PositionAvailability.available;
  StreamSubscription<Position>? _subscription;

  /// 권한·서비스 재확인이 진행 중인지 — 송신기가 주기마다 [start] 를 다시 불러도 겹쳐 돌지 않게 한다.
  bool _rechecking = false;

  /// [start] 가 불렸는지 — [stop] 이 먼저 불리면(권한 확인이 아직 안 끝난
  /// 사이) 뒤늦게 끝난 권한 확인이 구독을 다시 열지 않도록 막는다.
  bool _started = false;

  /// [requestPermission] 이 `false` 면 권한 창을 다시 띄우지 않고 현재 상태만 본다 — 재확인이 2초마다
  /// 돌 수 있어 사용자에게 창을 반복해 보이지 않으려는 것이다.
  Future<void> _init({bool requestPermission = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _availability = PositionAvailability.serviceDisabled;
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _availability = PositionAvailability.permissionDenied;
      return;
    }
    _availability = PositionAvailability.available;
  }

  @override
  void start() {
    if (_started) {
      // 권한·서비스 문제로 스트림을 못 연 채라면 다시 확인한다 — 기사가 설정에서 켠 것을 앱 재시작
      // 없이 알아채야 한다(F06-03).
      if (_availability != PositionAvailability.available) {
        unawaited(_recheck());
      }
      return;
    }
    _started = true;
    unawaited(_startStream());
  }

  @override
  Future<void> recheck() async {
    await _ready;
    await _recheck();
  }

  Future<void> _recheck() async {
    if (_rechecking) return;
    _rechecking = true;
    try {
      await _init(requestPermission: false);
      await _startStream();
    } finally {
      _rechecking = false;
    }
  }

  Future<void> _startStream() async {
    await _ready;
    if (!_started || _subscription != null) return;
    if (_availability != PositionAvailability.available) return;
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: buildLocationSettings(defaultTargetPlatform),
        ).listen(
          _onPosition,
          onError: (_) => _onStreamLost(),
          onDone: _onStreamLost,
        );
  }

  /// 스트림이 오류로 끊기거나 끝났다(운행 중 GPS 를 껐다 켠 경우 등) — 죽은
  /// 구독을 비우고 권한·서비스를 다시 확인해 연다. 비우지 않으면 [_startStream]
  /// 의 `_subscription != null` 검사에 막혀, 설정이 정상으로 돌아와도 그 회차가
  /// 끝날 때까지 위치 송신이 멈춘다(leak K-4). 서비스가 꺼진 탓이면 다시 열지
  /// 않고 [availability] 만 바꾼다 — 그 뒤 송신기의 주기 [start] 가 켜진 것을
  /// 알아채 연다(F06-03).
  void _onStreamLost() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_recheck());
  }

  @override
  void stop() {
    _started = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
    // 이 운행의 마지막 좌표를 다음 운행·비상 신고가 "지금 위치" 로 쓰지 않게 버린다(F06-04).
    _lastSample = null;
  }

  void _onPosition(Position position) {
    _lastSample = _toSample(position);
  }

  @override
  PositionSample? sample() {
    final last = _lastSample;
    if (last == null) return null;
    // 스트림이 끊긴 뒤(터널·주차장)의 마지막 좌표를 계속 보내지 않는다 — 비면 호출부가 새로 잰다(F06-04).
    final age = DateTime.now().difference(last.recordedAt);
    return age > PositionConstants.sampleMaxAge ? null : last;
  }

  @override
  PositionAvailability get availability => _availability;

  /// [sample] 이 스트림 구독을 못 여는 상황(비상 발신, BRIEF-BG2)의 보완 —
  /// [start] 없이 좌표를 한 번만 측정한다. 변환 규칙은 [_onPosition] 과
  /// 같은 [_toSample] 을 쓴다(두 벌 두지 않는다).
  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await _ready;
    // 권한·서비스 문제는 이미 알고 있으니 플랫폼을 다시 부르지 않는다.
    if (_availability != PositionAvailability.available) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return _toSample(position);
    } on TimeoutException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } on PermissionDeniedException {
      return null;
    }
  }

  /// 앱 종료 시 구독을 끊는다 — `di.dart` provider 의 `ref.onDispose` 에서
  /// 부른다. [stop] 과 같은 경로([start] 를 다시 부르면 재구독도 가능하나,
  /// 여기서는 provider 자체가 사라지는 시점이라 재사용되지 않는다).
  void dispose() {
    stop();
  }
}
