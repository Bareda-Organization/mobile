import 'package:manager_app/features/emergency/data/models/emergency_type.dart';

/// `POST /runs/{runId}/emergency` 요청 본문 — §4.14.
///
/// `clientKey` 는 필수다 — §1.7 멱등 대상 ②(오프라인 발신 후 재전송돼도
/// 중복 처리되지 않게). 즉시 전송이 실패해 오프라인 큐에 들어갈 때도 같은
/// 값을 그대로 재사용한다(`OfflineQueueRepository.sendOrQueue` 참고).
class EmergencyRaiseRequest {
  const EmergencyRaiseRequest({
    required this.type,
    required this.clientKey,
    this.memo,
    this.lat,
    this.lng,
    this.occurredAt,
  });

  final EmergencyType type;
  final String? memo;
  final double? lat;
  final double? lng;

  /// 오프라인 발신분의 실제 발생 시각 — 미전달 시 서버가 수신 시각을 쓴다.
  final DateTime? occurredAt;
  final String clientKey;

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    'client_key': clientKey,
    if (memo != null) 'memo': memo,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (occurredAt != null) 'occurred_at': occurredAt!.toIso8601String(),
  };
}
