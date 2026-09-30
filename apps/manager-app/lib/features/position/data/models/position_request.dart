import 'package:manager_app/core/time/wire_time.dart';

/// API_SPEC §4.12 요청 본문. `recorded_at` 은 **단말이 좌표를 측정한
/// 시각**이지 전송 시각이 아니다 — 전송이 지연돼도(재시도·네트워크 대기)
/// 서버는 실제로 그 위치에 있었던 시각을 받아야 근접 판정(NTF-04)이
/// 정확하다. 그래서 이 값은 호출부가 명시적으로 주고, 이 클래스가
/// 스스로 "지금" 을 채우지 않는다.
class PositionRequest {
  const PositionRequest({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.speed,
    this.heading,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? speed;
  final double? heading;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'recorded_at': toWireTime(recordedAt),
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
  };
}
