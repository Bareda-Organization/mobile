import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';

/// 카카오내비를 띄운 결과.
enum NaviLaunchResult {
  /// 카카오내비가 열렸다 — 경로 선택 화면이 뜬다.
  launched,

  /// 카카오내비가 설치돼 있지 않다 — 설치 안내가 필요하다.
  notInstalled,

  /// 설치돼 있는데 열지 못했다(앱 키·플랫폼 등록 오류 등).
  failed,
}

/// 서버가 정한 경로를 카카오내비에 넘기는 경계(RUN-08). 화면은 이 경계로만 열고 SDK 를 직접 부르지
/// 않는다 — 시험은 이 경계를 가짜로 바꿔 실제 앱을 열지 않는다.
abstract interface class KakaoNaviLauncher {
  /// [route] 의 경유지·목적지로 카카오내비 길안내를 연다.
  Future<NaviLaunchResult> launch(NavigationRoute route);

  /// 카카오내비 설치 안내 주소 — 기기에 맞는 스토어로 이어진다. [NaviLaunchResult.notInstalled] 뒤에 읽는다.
  Uri get installUri;
}

/// [route] 를 SDK 요청으로 바꾼다 — 서버 좌표(WGS84)이므로 `coordType` 을 `wgs84` 로 못 박는다
/// (SDK 서버 기본값은 KATEC 이라, 빠지면 좌표가 엉뚱한 곳을 가리킨다). 차종은 지정하지 않는다 —
/// 카카오내비 앱에 기사가 설정해 둔 차종을 따른다.
({Location destination, List<Location> viaList, NaviOption option})
kakaoNaviRequest(NavigationRoute route) {
  // SDK 좌표는 문자열이다 — `x` 가 경도, `y` 가 위도.
  Location location(NavigationPoint p) =>
      Location(name: p.name, x: '${p.lng}', y: '${p.lat}');
  return (
    destination: location(route.destination),
    viaList: route.waypoints.map(location).toList(),
    option: NaviOption(coordType: CoordType.wgs84),
  );
}

/// 공식 SDK(`kakao_flutter_sdk_navi`)로 여는 기본 구현.
class SdkKakaoNaviLauncher implements KakaoNaviLauncher {
  const new({required this.appKey});

  /// 카카오 네이티브 앱 키(`--dart-define=KAKAO_NAVI_APP_KEY`).
  final String appKey;

  @override
  Future<NaviLaunchResult> launch(NavigationRoute route) async {
    try {
      // 키가 있을 때만 초기화한다 — 같은 값으로 다시 불려도 안전하다.
      await KakaoSdk.init(nativeAppKey: appKey);
      if (!await NaviApi.instance.isKakaoNaviInstalled()) {
        return NaviLaunchResult.notInstalled;
      }
      final request = kakaoNaviRequest(route);
      await NaviApi.instance.navigate(
        destination: request.destination,
        option: request.option,
        viaList: request.viaList,
      );
      return NaviLaunchResult.launched;
    } on PlatformException {
      return NaviLaunchResult.failed;
    } on KakaoException {
      return NaviLaunchResult.failed;
    }
  }

  @override
  Uri get installUri => Uri.parse(NaviApi.webNaviInstall);
}
