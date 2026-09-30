import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// 다른 앱(전화·내비)을 여는 함수 — 열렸으면 `true`. 화면은 이 provider 로만 열고 `url_launcher` 를
/// 직접 부르지 않는다. 시험은 이 provider 를 **무엇을 열려 했는지 기록하는 함수**로 바꿔 실제 앱을 열지 않는다.
typedef UriOpener = Future<bool> Function(Uri uri);

/// 기본 구현 — 외부 앱으로 연다(`tel:` 은 전화 앱, 내비 스킴은 내비 앱).
final Provider<UriOpener> uriOpenerProvider = Provider<UriOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// 기기 설정 화면의 종류 — 위치 권한은 앱 설정, 위치 서비스 꺼짐은 위치 설정에서 고친다.
enum DeviceSettingsPage { app, location }

/// 기기 설정 화면을 여는 함수 — [uriOpenerProvider] 와 같은 이유로 시험이 바꿔 끼운다.
typedef SettingsOpener = Future<bool> Function(DeviceSettingsPage page);

/// 기본 구현 — `geolocator` 가 이미 플랫폼별 설정 열기를 갖고 있어 새 의존성이 필요 없다.
final Provider<SettingsOpener> settingsOpenerProvider =
    Provider<SettingsOpener>(
      (ref) =>
          (page) => switch (page) {
            DeviceSettingsPage.app => Geolocator.openAppSettings(),
            DeviceSettingsPage.location => Geolocator.openLocationSettings(),
          },
    );
