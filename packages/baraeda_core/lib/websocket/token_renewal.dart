import 'dart:convert';

/// 접근 토큰 만료 전 무중단 갈아타기의 시간 값(`API_SPEC §7.2` ·
/// R46-LATERRT C-14) — 기본값이 운영 값이고 시험이 줄여 쓴다.
class TokenRenewalTiming {
  /// 값을 그대로 받는다.
  const new({
    this.lead = const Duration(seconds: 60),
    this.minDelay = const Duration(seconds: 5),
    this.subscribeSettle = const Duration(milliseconds: 1500),
    this.dedupTail = const Duration(seconds: 5),
  });

  /// 토큰 만료 이 시간 전에 두 번째 연결을 연다. 클라이언트 시계가 서버보다
  /// 느리면 갈아타기가 만료 뒤로 밀리고, 그때는 기존 `TOKEN_EXPIRED` 재연결
  /// 경로가 받는다.
  final Duration lead;

  /// 만료가 이미 임박했거나 수명이 짧은 토큰이어도 갈아타기를 이 간격보다
  /// 촘촘히 반복하지 않는다.
  final Duration minDelay;

  /// 서버는 STOMP `RECEIPT` 를 보내지 않아(2026-10-01 실측) 구독 성공을 응답으로
  /// 알 수 없다 — 거부는 `ERROR`·닫힘으로만 드러난다. 새 연결에 구독을 모두 건
  /// 뒤 이 시간 동안 거부 신호가 없으면 확인된 것으로 보고 옛 연결을 닫는다.
  final Duration subscribeSettle;

  /// 옛 연결을 닫은 뒤에도 쌍둥이 방송이 새 연결로 늦게 도착할 수 있어 중복
  /// 거르기를 이 시간 더 유지한다.
  final Duration dedupTail;
}

/// JWT 페이로드의 `exp`(초)를 시각으로 읽는다. 로그인·재발급 응답에 만료 시각
/// 필드가 없어(`API_SPEC §2`) 토큰 자체에서 읽는다. 서명은 검증하지 않는다 —
/// 만료 시각을 알 뿐 신뢰 판단에 쓰지 않으며, 틀린 값이어도 결과는 갈아타기가
/// 일찍·늦게 시작하는 데 그친다(늦으면 기존 `TOKEN_EXPIRED` 경로). 읽을 수
/// 없으면 `null`.
DateTime? readJwtExpiry(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final exp = claims is Map<String, dynamic> ? claims['exp'] : null;
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
        : null;
  } on FormatException {
    return null;
  }
}
