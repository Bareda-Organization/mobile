import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:manager_app/features/navigation/domain/kakao_navi_launcher.dart';
import 'package:manager_app/features/navigation/domain/models/navigation_route.dart';

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
