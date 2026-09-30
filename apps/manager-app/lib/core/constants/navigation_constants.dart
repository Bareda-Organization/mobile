/// 외부 내비(RUN-08) 설정.
abstract final class NavigationConstants {
  /// 카카오내비 앱 키 — **사용자 자원**(카카오 개발자 콘솔 발급)이라 저장소에
  /// 없다. 빌드에 `--dart-define=KAKAO_NAVI_APP_KEY=<키>` 로 넣는다. 비어 있으면
  /// 운행 화면이 [외부 내비] 버튼을 그리지 않는다.
  static const kakaoAppKey = String.fromEnvironment('KAKAO_NAVI_APP_KEY');
}
