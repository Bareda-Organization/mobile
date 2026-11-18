import 'package:manager_app/features/navigation/domain/models/navigation_route.dart';

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
