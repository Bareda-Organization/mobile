import 'package:baraeda_core/id/as_id_string.dart';
import 'package:baraeda_core/websocket/ws_event_type.dart';

/// `API_SPEC §7` 공통 봉투.
///
/// 표는 `run_id` 를 `string` 으로 문서화하지만 실제 서버
/// `WebSocketEnvelope.java` 는 `Long runId` 를 그대로 내보낸다(Ruling 275) —
/// [asIdString] 을 거쳐 흡수하고, `payload` 는 원문 `Map` 그대로 둔 채 호출부가
/// `event` 에 맞는 `ws_payloads.dart` 의 `Ws*Payload.fromJson` 으로 다시
/// 파싱한다(그 파싱도 안의 id 필드마다 같은 흡수를 거친다).
class WebSocketEnvelope {
  const WebSocketEnvelope({
    required this.event,
    required this.eventWireValue,
    required this.runId,
    required this.occurredAt,
    required this.payload,
  });

  factory WebSocketEnvelope.fromJson(Map<String, dynamic> json) {
    final wireValue = json['event'] as String?;
    return WebSocketEnvelope(
      event: WsEventType.fromWireValueOrNull(wireValue),
      eventWireValue: wireValue,
      runId: asIdString(json['run_id']),
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      payload: (json['payload'] as Map).cast<String, dynamic>(),
    );
  }

  /// 알려진 이벤트면 채워진다. 서버가 새 이벤트를 추가하면 `null` — 그 경우
  /// 파싱 자체가 죽지 않고 이 필드만 비게 만들어, 호출부가 무시하거나 로그만
  /// 남기도록 한다.
  final WsEventType? event;

  /// `event` 원문 문자열 — [event] 가 `null` 일 때도(미지 이벤트) 무엇이
  /// 왔는지 로그에 남기기 위해 보존한다.
  final String? eventWireValue;

  /// 대상 회차 id. [asIdString] 으로 흡수한 문자열 — 서버가 `Long` 을 보내든
  /// 사양대로 `string` 을 보내든 이 필드는 항상 `String` 이다.
  final String runId;

  final DateTime occurredAt;

  /// 이벤트별 본문 원문. `event` 값에 맞춰 `ws_payloads.dart` 의
  /// `Ws*Payload.fromJson(payload)` 로 다시 파싱한다.
  final Map<String, dynamic> payload;
}
