import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:manager_app/core/location/position_source.dart';

/// 실제 플랫폼 채널 없이 권한·위치 서비스·좌표 스트림을 시험이 직접
/// 제어하는 가짜 — `token_storage_test.dart` 의 `_FakeSecureStoragePlatform`
/// 과 같은 이유로 `extends GeolocatorPlatform` 를 쓴다(`GeolocatorPlatform()`
/// 기본 생성자가 이미 유효한 검증 토큰을 물려주므로 `MockPlatformInterfaceMixin`
/// 이 따로 필요 없다 — geolocator_platform_interface 는 dev_dependency).
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  bool serviceEnabled = true;
  final _positionController = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async => checkPermissionResult;

  @override
  Future<LocationPermission> requestPermission() async =>
      checkPermissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _positionController.stream;

  void emit(Position position) => _positionController.add(position);
}

Position _position({
  double speed = 1,
  double heading = 1,
  DateTime? timestamp,
}) => Position(
  latitude: 37.5,
  longitude: 127,
  timestamp: timestamp ?? DateTime.utc(2026, 9, 26),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

void main() {
  test('권한·위치 서비스가 정상이면 스트림 좌표를 캐시해 sample() 로 낸다', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource();
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
    expect(sample.speed, 5);
    expect(sample.heading, 90);
  });

  test('recordedAt 은 플랫폼이 준 측정 시각 그대로다(전송 시각이 아니다)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource();
    await source.ready;

    final measuredAt = DateTime.utc(2020);
    platform.emit(_position(timestamp: measuredAt));
    await Future<void>.delayed(Duration.zero);

    expect(source.sample()!.recordedAt, measuredAt);
  });

  test('iOS 음수 속도·방향은 필드를 빼고 보낸다(§4.12 범위 밖)', () async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource();
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
    final source = GeolocatorPositionSource();
    await source.ready;

    expect(source.sample(), isNull);
    expect(source.availability, PositionAvailability.permissionDenied);
  });

  test('위치 서비스 꺼짐 → sample() null, availability serviceDisabled', () async {
    final platform = _FakeGeolocatorPlatform()..serviceEnabled = false;
    GeolocatorPlatform.instance = platform;
    final source = GeolocatorPositionSource();
    await source.ready;

    expect(source.sample(), isNull);
    expect(source.availability, PositionAvailability.serviceDisabled);
  });
}
