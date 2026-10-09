import 'package:baraeda_core/push/device_registration_storage.dart';
import 'package:baraeda_core/push/push_token_source.dart';

/// Firebase 를 붙이기 전의 기본 공급자(Ruling 510) — 기기별 자리표시 토큰을
/// 준다. 서버는 이 값을 FCM 에 보냈다가 거부(`INVALID_ARGUMENT`)를 받으면
/// 행을 해지하고, 로그 전용 발송기(`LoggingPushSender`)는 토큰을 쓰지 않으므로
/// 해가 없다. 대신 로그인 뒤 등록 · 로그아웃 해지 · 설정 스위치가 키 없는
/// 환경(스테이징 · 시험)에서도 끝까지 돈다.
class PlaceholderPushTokenSource implements PushTokenSource {
  /// 기기 식별자를 만드는 저장소를 받는다 — 토큰이 그 값에서 정해져 앱을 다시
  /// 켜도 같다.
  new(this._storage);

  final DeviceRegistrationStorage _storage;

  static const _tokenPrefix = 'placeholder-';

  /// [token] 이 이 공급자가 만든 자리표시 값인가 — 그렇다면 이 기기는 실제로는 푸시를 받지 못한다.
  /// 화면이 "푸시로도 알려 드려요" 같은 약속을 할지 가르는 데 쓴다(M-P3).
  static bool isPlaceholder(String? token) =>
      token != null && token.startsWith(_tokenPrefix);

  @override
  Future<String?> currentToken() async =>
      '$_tokenPrefix${await _storage.readOrCreateDeviceId()}';

  @override
  Stream<void> get onMessage => const Stream.empty();
}
