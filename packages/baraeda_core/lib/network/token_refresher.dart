// 필드는 비공개로 두고 생성자 파라미터만 공개 이름을 쓴다(`ApiClient`·WS
// 양쪽에서 `refreshDio:` · `tokenStorage:` · `clientType:` 처럼 읽기 좋은
// 이름으로 넘겨받기 위해서다) — `token_storage.dart` 와 같은 이유로
// initializing formal 대신 초기화 리스트로 대입한다.
// ignore_for_file: prefer_initializing_formals

import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';

/// `POST /auth/refresh`(API_SPEC §2.6) 로 access·refresh 토큰을 재발급하는
/// 단일 창구 — `ApiClient` 의 REST `401` 재시도와 `BaraedaWebSocketClient`
/// 의 WS `TOKEN_EXPIRED` 처리가 **같은 인스턴스**를 공유한다.
///
/// 공유해야 하는 이유는 서버의 refresh 회전 방식에 있다 — 백엔드
/// `RefreshCommandService.refresh` 는 refresh 토큰을 조건부 UPDATE 로
/// **1회용으로 회전**시킨다(동시 요청이 둘 다 "미해지" 를 읽어도 무효화에
/// 성공한 한 건만 새 토큰을 받는다, `BR-061`). REST 401 재발급과 WS 재발급이
/// 같은 refresh 토큰으로 동시에 나가면, 이기지 못한 쪽은 **여전히 유효한
/// 세션인데도** `401 TOKEN_EXPIRED` 를 받아 로그인 만료로 잘못 취급된다.
/// [refresh] 를 동시에 여러 번 불러도 진행 중인 시도 하나에 합류시켜
/// HTTP 호출 자체를 1회로 묶으면 이 경합이 구조적으로 사라진다 — 웹
/// `refreshClient.ts` 가 같은 문제를 같은 방식으로 푼 것과 동일하다.
class TokenRefresher {
  /// [refreshDio] 는 인터셉터가 붙지 않은 별도 dio 인스턴스여야 한다 —
  /// `ApiClient` 문서의 재귀 방지 근거를 그대로 따른다.
  TokenRefresher({
    required Dio refreshDio,
    required TokenStorage tokenStorage,
    required String clientType,
  }) : _refreshDio = refreshDio,
       _tokenStorage = tokenStorage,
       _clientType = clientType;

  final Dio _refreshDio;
  final TokenStorage _tokenStorage;
  final String _clientType;

  Future<String?>? _pending;

  /// 새 access 토큰을 재발급한다. 이미 진행 중인 재발급이 있으면 새 HTTP
  /// 호출 없이 그 결과에 합류한다 — 완료 뒤에는 다음 호출이 새 시도를
  /// 연다(결과를 캐시해 계속 재사용하지 않는다).
  ///
  /// 실패(무효 refresh·네트워크 오류·refresh 토큰 부재)하면 저장된 토큰을
  /// 지우고 `null` 을 돌려준다 — 호출부는 이를 "재로그인 필요"로 취급한다.
  Future<String?> refresh() {
    return _pending ??= _doRefresh().whenComplete(() => _pending = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      // `refreshDio` 는 인터셉터가 붙지 않은 별도 인스턴스로 받는다 — 재귀
      // 방지 근거는 `ApiClient` 문서를 그대로 따른다(이 클래스는 그 판단을
      // 다시 내리지 않고 주입받은 인스턴스를 그대로 쓴다).
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {'X-Client-Type': _clientType}),
      );
      final body = response.data;
      final newAccessToken = body?['access_token'] as String?;
      final newRefreshToken = body?['refresh_token'] as String?;
      if (newAccessToken == null || newRefreshToken == null) {
        await _tokenStorage.clear();
        return null;
      }
      await _tokenStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );
      return newAccessToken;
    } on DioException {
      await _tokenStorage.clear();
      return null;
    }
  }
}
