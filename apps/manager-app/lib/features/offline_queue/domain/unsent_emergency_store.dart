/// 서버가 거절해 지워진 비상 신고의 요약 — 건수 · 마지막 시각 · 그때의 학원 전화번호(Ruling 886).
/// 학생 이름이 없는 정보라 계정을 정리해도 지우지 않는다. 승하차·도착 행의 거절 안내(Ruling 892)도 같은 모양
/// (번호 `null`)으로 남긴다.
class UnsentEmergency {
  const new({required this.count, required this.lastAt, this.contact});

  factory fromJson(Map<String, dynamic> json) => UnsentEmergency(
    count: json['count'] as int,
    lastAt: DateTime.parse(json['last_at'] as String),
    contact: json['contact'] as String?,
  );

  /// 전송되지 못한 비상 신고 건수.
  final int count;

  /// 가장 마지막으로 지워진 시각.
  final DateTime lastAt;

  /// 그때의 학원 전화번호 — 없으면 `null`.
  final String? contact;

  Map<String, dynamic> toJson() => {
    'count': count,
    'last_at': lastAt.toIso8601String(),
    'contact': contact,
  };
}

/// [UnsentEmergency] 를 이 기기에 남기고 사용자가 [확인] 할 때 지운다.
/// 로그아웃 · 세션 만료 · 앱 종료로는 지우지 않는다.
abstract interface class UnsentEmergencyStore {
  Future<UnsentEmergency?> read();

  Future<void> write(UnsentEmergency value);

  Future<void> clear();
}
