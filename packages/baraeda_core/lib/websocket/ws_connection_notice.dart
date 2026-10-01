/// 실시간 연결 끊김 안내의 제목 — 웹(`academy-web` 의 `wsConnectionNotice.ts`)과
/// 두 앱이 같은 문구를 쓴다(`API_SPEC §7.2` 사용자 표시 행, R46-FIXCONN C-12).
/// 같은 사건을 화면마다 다르게 알리면 지원 문의 때 "무슨 문구가 떴나" 로 상태를
/// 가를 수 없다. 문구를 바꾸면 웹 파일도 같이 고친다 — 같은지는
/// `ws_connection_notice_test.dart` 가 웹 파일과 대조한다.
abstract final class WsConnectionNotice {
  /// 끊겨 재연결 대기·시도 중.
  static const reconnectingTitle = '재연결 시도 중입니다';

  /// 재연결을 포기했다 — 기본 정책은 포기하지 않아 상한을 준 정책에서만 쓰인다.
  static const gaveUpTitle = '실시간 연결 끊김';

  /// 구독 권한이 없다 — 다시 해도 같은 결과다.
  static const forbiddenTitle = '실시간 조회 권한 없음';
}
