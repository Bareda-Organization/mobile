import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';

/// 실제 플랫폼 채널 없이 권한·위치 서비스·좌표 스트림을 시험이 직접
/// 제어하는 가짜 — `token_storage_test.dart` 의 `_FakeSecureStoragePlatform`
/// 과 같은 이유로 `extends GeolocatorPlatform` 를 쓴다(`GeolocatorPlatform()`
/// 기본 생성자가 이미 유효한 검증 토큰을 물려주므로 `MockPlatformInterfaceMixin`
/// 이 따로 필요 없다 — geolocator_platform_interface 는 dev_dependency).
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  bool serviceEnabled = true;
  var _positionController = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async => checkPermissionResult;

  @override
  Future<LocationPermission> requestPermission() async => checkPermissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  /// 위치 스트림이 열린 횟수 — 재확인이 스트림(포그라운드 서비스 알림)을 켜지 않는지 본다.
  int streamOpens = 0;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamOpens++;
    return _positionController.stream;
  }

  void emit(Position position) => _positionController.add(position);

  /// 운행 중 GPS 를 껐다 켜는 것처럼 스트림이 오류를 내는 순간(leak K-4).
  void emitError(Object error) => _positionController.addError(error);

  /// 스트림이 끝나는 순간 — 다시 열면 새 스트림이 나가도록 컨트롤러를 갈아 둔다.
  Future<void> endStream() {
    final ended = _positionController;
    _positionController = StreamController<Position>.broadcast();
    return ended.close();
  }

  /// `sampleOnce` 시험용 — 값을 그대로 낼지, 예외를 던질지 고른다(BRIEF-BG2).
  Position? currentPositionResult;
  Exception? currentPositionError;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    if (currentPositionError != null) throw currentPositionError!;
    return Future.value(currentPositionResult);
  }
}

Position _position({
  double speed = 1,
  double heading = 1,
  DateTime? timestamp,
}) => Position(
  latitude: 37.5,
  longitude: 127,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

void main() {
  // Ruling 360 — Android 는 포그라운드 서비스 알림, iOS 는 사용 중 권한으로
  // 시작한 백그라운드 갱신 유지. 플랫폼 분기를 순수 함수로 빼서 시험이
  // 실제 GPS 없이 두 분기를 각각 검사할 수 있게 한다(BRIEF-BG 할 일 1).
  group('buildLocationSettings', () {
    test('Android 는 포그라운드 서비스 알림 설정을 싣는다', () {
      final settings = buildLocationSettings(TargetPlatform.android);

      expect(settings, isA<AndroidSettings>());
      final android = settings as AndroidSettings;
      expect(android.foregroundNotificationConfig, isNotNull);
      expect(android.foregroundNotificationConfig!.enableWakeLock, isTrue);
    });

    test('iOS 는 사용 중 권한으로 시작한 백그라운드 갱신을 켠다', () {
      final settings = buildLocationSettings(TargetPlatform.iOS);

      expect(settings, isA<AppleSettings>());
      final apple = settings as AppleSettings;
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    });

    test('그 밖 플랫폼은 기본 LocationSettings 를 쓴다(정확도는 유지)', () {
      final settings = buildLocationSettings(TargetPlatform.macOS);

      expect(settings.runtimeType, LocationSettings);
      expect(settings.accuracy, LocationAccuracy.high);
    });
  });

  // §4.12 `speed` 의 상한은 999.99 km/h — 넘으면 서버가 422 로 거부해 그 위치가 통째로 사라진다.
  test('속도가 사양 상한(999.99 km/h)을 넘으면 상한으로 줄여 보낸다', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;
    platform.emit(_position(speed: 400, heading: 90));
    await Future<void>.delayed(Duration.zero);

    expect(source.sample()!.speed, 999.99);
  });

  test('권한·위치 서비스가 정상이면 스트림 좌표를 캐시해 sample() 로 낸다', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    expect(source.availability, PositionAvailability.available);
    // 아직 첫 좌표를 못 받았을 때는 null — 지어내지 않는다.
    expect(source.sample(), isNull);

    platform.emit(_position(speed: 5, heading: 90));
    await Future<void>.delayed(Duration.zero);

    final sample = source.sample();
    expect(sample, isNotNull);
    expect(sample!.lat, 37.5);
    expect(sample.lng, 127);
    // 기기는 m/s 로 주고 §4.12 는 km/h 로 받는다(L6 · 861 ⑩) — 5 m/s = 18 km/h.
    expect(sample.speed, closeTo(18, 0.001));
    expect(sample.heading, 90);
  });

  test('recordedAt 은 플랫폼이 준 측정 시각 그대로다(전송 시각이 아니다)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    final measuredAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 1),
    );
    platform.emit(_position(timestamp: measuredAt));
    await Future<void>.delayed(Duration.zero);

    expect(source.sample()!.recordedAt, measuredAt);
  });

  test('iOS 음수 속도·방향은 필드를 빼고 보낸다(§4.12 범위 밖)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    platform.emit(_position(speed: -1, heading: -1));
    await Future<void>.delayed(Duration.zero);

    final sample = source.sample()!;
    expect(sample.speed, isNull);
    expect(sample.heading, isNull);
  });

  test('위치 권한 거부 → sample() null, availability permissionDenied', () async {
    final platform = _FakeGeolocatorPlatform()
      ..checkPermissionResult = LocationPermission.denied;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    expect(source.sample(), isNull);
    expect(source.availability, PositionAvailability.permissionDenied);
  });

  test('위치 서비스 꺼짐 → sample() null, availability serviceDisabled', () async {
    final platform = _FakeGeolocatorPlatform()..serviceEnabled = false;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    expect(source.sample(), isNull);
    expect(source.availability, PositionAvailability.serviceDisabled);
  });

  // F06-04 — 캐시된 좌표는 운행이 끝나거나 GPS 가 끊긴 뒤에도 "지금 위치" 로 쓰이면 안 된다.
  // 비상 신고·다음 운행 첫 송신이 몇 시간 전 좌표를 싣고 나간다.
  test('stop() 하면 캐시 좌표를 버린다(다음 운행·비상이 옛 좌표를 쓰지 않는다)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;
    platform.emit(_position());
    await Future<void>.delayed(Duration.zero);
    expect(source.sample(), isNotNull);

    source.stop();

    expect(source.sample(), isNull);
  });

  test('측정한 지 오래된 좌표는 sample() 이 내지 않는다(GPS 가 끊긴 뒤 재전송 방지)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;

    platform.emit(
      _position(
        timestamp: DateTime.now().toUtc().subtract(
          PositionConstants.sampleMaxAge + const Duration(seconds: 1),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(source.sample(), isNull);
  });

  // F06-03 — 권한·위치 서비스는 생성 때 한 번만 확인했다. 기사가 설정에서 켜도 앱을 다시 켤 때까지
  // 송신이 살아나지 않았다. 송신기가 주기마다 start() 를 다시 부르면 그때 다시 확인한다.
  test('위치 서비스를 나중에 켜면 start() 재호출로 송신이 되살아난다', () async {
    final platform = _FakeGeolocatorPlatform()..serviceEnabled = false;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;
    expect(source.availability, PositionAvailability.serviceDisabled);

    platform.serviceEnabled = true;
    source.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    platform.emit(_position());
    await Future<void>.delayed(Duration.zero);

    expect(source.availability, PositionAvailability.available);
    expect(source.sample(), isNotNull);
  });

  test('권한을 나중에 허용해도 start() 재호출로 되살아난다', () async {
    final platform = _FakeGeolocatorPlatform()
      ..checkPermissionResult = LocationPermission.denied;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource()..start();
    await source.ready;
    expect(source.availability, PositionAvailability.permissionDenied);

    platform.checkPermissionResult = LocationPermission.whileInUse;
    source.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    platform.emit(_position());
    await Future<void>.delayed(Duration.zero);

    expect(source.availability, PositionAvailability.available);
    expect(source.sample(), isNotNull);
  });

  // M2-02 — 운행 시작 전 화면이 권한·서비스만 다시 본다. 스트림은 start() 가 있어야만 열린다.
  test('recheck() 는 start() 없이 상태만 갱신하고 스트림은 열지 않는다', () async {
    final platform = _FakeGeolocatorPlatform()
      ..checkPermissionResult = LocationPermission.denied;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource();
    await source.ready;
    expect(source.availability, PositionAvailability.permissionDenied);

    platform.checkPermissionResult = LocationPermission.whileInUse;
    await source.recheck();

    expect(source.availability, PositionAvailability.available);
    expect(platform.streamOpens, 0);
  });

  // R46-KFIXFE(leak K-4) — 스트림이 오류·종료돼도 구독 변수가 남아 `_startStream` 이 다시 열지 않았다.
  // availability 는 available 인 채라 송신기도 재시작을 안 불러, 그 회차가 끝날 때까지 위치 송신이 멈췄다.
  group('위치 스트림이 오류·종료돼도', () {
    test('오류가 나면 구독을 비우고 다시 열어 좌표가 계속 들어온다', () async {
      final platform = _FakeGeolocatorPlatform();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource()..start();
      await source.ready;
      await Future<void>.delayed(Duration.zero);
      expect(platform.streamOpens, 1);

      platform.emitError(Exception('GPS 스트림 오류'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(platform.streamOpens, 2);
      platform.emit(_position());
      await Future<void>.delayed(Duration.zero);
      expect(source.sample(), isNotNull);
    });

    test('스트림이 끝나도 다시 열어 좌표가 계속 들어온다', () async {
      final platform = _FakeGeolocatorPlatform();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource()..start();
      await source.ready;
      await Future<void>.delayed(Duration.zero);

      await platform.endStream();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(platform.streamOpens, 2);
      platform.emit(_position());
      await Future<void>.delayed(Duration.zero);
      expect(source.sample(), isNotNull);
    });

    test('위치 서비스를 끈 탓이면 다시 열지 않고 상태만 알리다가, 켜면 다음 start() 에서 연다', () async {
      final platform = _FakeGeolocatorPlatform();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource()..start();
      await source.ready;
      await Future<void>.delayed(Duration.zero);

      platform
        ..serviceEnabled = false
        ..emitError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(source.availability, PositionAvailability.serviceDisabled);
      expect(platform.streamOpens, 1);

      platform.serviceEnabled = true;
      source.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(platform.streamOpens, 2);
    });
  });

  // BRIEF-BG2 — 스트림 좌표가 없을 때(비상 발신, 동승자 단말·송신 두절
  // 기사 단말) 포그라운드 서비스를 켜지 않고 좌표를 한 번만 얻는다.
  group('sampleOnce', () {
    test(
      'getCurrentPosition 결과를 sample() 과 같은 변환 규칙으로 낸다(음수 속도·방향 제외)',
      () async {
        final platform = _FakeGeolocatorPlatform()
          ..currentPositionResult = _position(speed: -1, heading: -1);
        GeolocatorPlatform.instance = platform;
        final source = GeolocatorPositionSource();
        await source.ready;

        final result = await source.sampleOnce();

        expect(result, isNotNull);
        expect(result!.lat, 37.5);
        expect(result.lng, 127);
        expect(result.speed, isNull);
        expect(result.heading, isNull);
      },
    );

    test('스트림을 열지 않는다(start() 를 부르지 않는다) — sample() 은 그대로 null', () async {
      final platform = _FakeGeolocatorPlatform()
        ..currentPositionResult = _position();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource();
      await source.ready;

      final result = await source.sampleOnce();

      expect(result, isNotNull);
      // 캐시(_lastSample)에 남기지 않는다 — 스트림 구독과 별개 경로다.
      expect(source.sample(), isNull);
    });

    test('제한 시간 안에 못 받으면(TimeoutException) null 을 낸다', () async {
      final platform = _FakeGeolocatorPlatform()
        ..currentPositionError = TimeoutException('no fix');
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource();
      await source.ready;

      expect(await source.sampleOnce(), isNull);
    });

    test('위치 서비스 거부(LocationServiceDisabledException)면 null 을 낸다', () async {
      final platform = _FakeGeolocatorPlatform()
        ..currentPositionError = const LocationServiceDisabledException();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource();
      await source.ready;

      expect(await source.sampleOnce(), isNull);
    });

    test('권한이 이미 거부 상태면 플랫폼을 부르지 않고 null 을 낸다', () async {
      final platform = _FakeGeolocatorPlatform()
        ..checkPermissionResult = LocationPermission.denied
        ..currentPositionResult = _position();
      GeolocatorPlatform.instance = platform;
      final source = GeolocatorPositionSource();
      await source.ready;

      expect(await source.sampleOnce(), isNull);
    });
  });
}
