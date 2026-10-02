/// 단말 푸시 토큰 공급자 포트(NTF-12 · Ruling 510) — FCM · APNs 같은 실제
/// 발급 수단은 이 인터페이스 뒤에 둔다.
///
/// 키·설정 파일(`google-services.json` · `GoogleService-Info.plist`)이 없는
/// 환경에서도 앱이 빌드·시험되도록 기본 구현은
/// `PlaceholderPushTokenSource` 이고, Firebase 구현은 배포 때
/// `pushTokenSourceProvider` 한 줄로 바꾼다
/// (`docs/backend/infra/DEPLOYMENT.md` 의 "외부 연동 준비물").
abstract interface class PushTokenSource {
  /// 이 단말의 푸시 토큰. **줄 수 없으면 `null`**(Firebase 미설정 · 알림 권한
  /// 거부) — 등록을 건너뛴다.
  Future<String?> currentToken();

  /// 앱이 열려 있는 동안 푸시가 도착할 때마다 한 번씩 — 알림 목록을 다시
  /// 불러오는 연결 자리다. 기본 구현은 아무것도 내지 않는다.
  Stream<void> get onMessage;
}
