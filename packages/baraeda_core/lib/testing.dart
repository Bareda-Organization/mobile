/// 시험 전용 도우미 — 앱 · 패키지 시험이 파일마다 복사해 쓰던 대역을 한 곳에 둔다.
/// 제품 코드는 가져오지 않는다(`baraeda_core.dart` 배럴에 넣지 않는다).
library;

import 'dart:async';

import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/time/clock.dart';

/// 정해 둔 시각만 알려 주는 [Clock] — [current] 를 바꾸면 시간이 흐른 것처럼 쓴다.
class FixedClock implements Clock {
  /// [current] 로 시작한다.
  new(this.current);

  /// [now] 가 돌려주는 시각.
  DateTime current;

  @override
  DateTime now() => current;
}

/// access 토큰 읽기가 끝내 응답하지 않는 [TokenStorage] — 운행 채널(WebSocket)이 연결을 시작하지 못하게
/// 붙잡아 두는 시험용이다. 플랫폼 보안 저장소를 건드리지 않는다.
class NeverResolvingTokenStorage extends TokenStorage {
  /// 저장 키는 시험이 쓰지 않는 값이다.
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;

  /// 로그인 기록은 없는 기기다 — 바로 `null`.
  @override
  Future<String?> readRefreshToken() async => null;
}

/// 실서버 계약 시험이 붙을 주소. **주소를 받지 못하면 던진다.**
///
/// 기본값으로 조용히 `localhost:8080`(조율자의 시드 서버)에 붙는 경로를 없애는 것이 이 함수의 전부다 —
/// `--dart-define=API_BASE_URL` 을 빠뜨린 실행이 시드 DB 에 실제 레코드를 만든 일이 있다. 안내 문구가 아니라
/// 구조로 막는다. 백엔드 없이 나머지 시험만 돌리려면 `flutter test --exclude-tags real_backend`.
String requireRealBackendBaseUrl() {
  if (!const bool.hasEnvironment('API_BASE_URL')) {
    throw StateError(
      '실서버 계약 시험에는 대상 주소가 필요하다. '
      'flutter test --dart-define=API_BASE_URL=http://localhost:<전용포트>/api/v1 로 실행하라. '
      '주소를 생략하면 기본값 8080(조율자 시드 서버)으로 실제 요청이 나간다. '
      '백엔드 없이 돌리려면 --exclude-tags real_backend 를 쓴다.',
    );
  }
  return const String.fromEnvironment('API_BASE_URL');
}
