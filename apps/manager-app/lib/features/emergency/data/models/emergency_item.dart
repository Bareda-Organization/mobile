import 'package:manager_app/features/emergency/data/models/emergency_type.dart';

/// `GET /runs/{runId}/emergencies` 의 `items[]` 원소 — §4.15.
///
/// `acked` 는 이 화면 진입 시 조회 + 수동 새로고침으로만 갱신한다. 실시간
/// 반영(WS `emergency_acked`)은 F4 범위 — 이 라운드는 WebSocket 클라이언트를
/// 두지 않는다(지시서 범위 제한).
class EmergencyItem {
  const new({
    required this.emergencyId,
    required this.type,
    required this.raisedAt,
    required this.cancelableUntil,
    required this.acked,
    this.ackedAt,
    this.ackedByName,
    this.canceledAt,
  });

  factory fromJson(Map<String, dynamic> json) {
    return EmergencyItem(
      emergencyId: json['emergency_id'] as String,
      type:
          EmergencyType.fromWireValueOrNull(json['type'] as String?) ??
          EmergencyType.etc,
      raisedAt: DateTime.parse(json['raised_at'] as String),
      cancelableUntil: DateTime.parse(json['cancelable_until'] as String),
      acked: json['acked'] as bool,
      ackedAt: json['acked_at'] == null
          ? null
          : DateTime.parse(json['acked_at'] as String),
      ackedByName: json['acked_by_name'] as String?,
      canceledAt: json['canceled_at'] == null
          ? null
          : DateTime.parse(json['canceled_at'] as String),
    );
  }

  final String emergencyId;
  final EmergencyType type;
  final DateTime raisedAt;
  final DateTime cancelableUntil;
  final bool acked;
  final DateTime? ackedAt;
  final String? ackedByName;

  /// 취소된 발신도 레코드는 존치되므로(§4.14 "레코드는 존치") 이 필드로
  /// 구분한다 — `null` 이 아니면 취소된 발신.
  final DateTime? canceledAt;
}

/// `GET /runs/{runId}/emergencies` 응답 — §4.15. §1.8 의 페이징 봉투가
/// 이 엔드포인트 절에는 명시돼 있지 않아(`page`·`size`·`total_count` 언급
/// 부재) `items[]` 하나만 옮긴다.
class EmergencyListResponse {
  const new({required this.items});

  factory fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>;
    return EmergencyListResponse(
      items: rawItems
          .map((item) => EmergencyItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<EmergencyItem> items;
}
