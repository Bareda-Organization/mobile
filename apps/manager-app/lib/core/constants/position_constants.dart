/// 위치 전송 정책 상수 — API_SPEC §4.12 위치 업로드 주기.
abstract final class PositionConstants {
  /// 위치 전송 주기.
  ///
  /// 2026-09-14 사용자 결정으로 8초 → 2초로 단축했다(`F4-B` 2단계
  /// `COMMON-B2.md` §2) — 학부모·동승자 화면의 마커 보간을 "다음 좌표
  /// 도착 시각까지 균등하게 편다" 방식으로 바꾸는 것과 짝을 이룬다.
  ///
  /// ⚠ 값을 여기 하나로 뺀 이유 — 이 변경은 방송량을 산술적으로 4배로
  /// 올린다(2026-09-09 실측: 목표 규모 방송량 40,000건/s 가 이미 통과선
  /// 그 자체였고 80,000건/s 는 붕괴). 재측정 전까지는 **되돌릴 수 있어야
  /// 한다** — 상수 하나만 고치면 되게 한다.
  static const transmissionInterval = Duration(seconds: 2);

  /// 캐시된 좌표를 "지금 위치" 로 인정하는 최대 나이 — 이보다 오래된 측정값은 GPS 가 끊겼거나 앞 운행의
  /// 잔재라 송신·비상 신고에 쓰지 않는다(F06-04). 송신 주기의 5배.
  static const sampleMaxAge = Duration(seconds: 10);

  /// 마지막 성공 전송이 이 시간 안이면 운행 화면이 "위치 전송 중" 으로 본다 — 송신 주기의 3배(한두 번 실패해도
  /// 정상으로 본다).
  static const linkHealthyWithin = Duration(seconds: 6);

  /// 마지막 성공 전송이 이 시간 넘게 없으면 "전송 안 됨" 이다 — 학부모 화면이 "마지막 확인 위치 N분 전" 으로
  /// 바뀌기 전에 기사가 먼저 알도록 잡은 값(R46).
  static const linkLostAfter = Duration(seconds: 30);
}
