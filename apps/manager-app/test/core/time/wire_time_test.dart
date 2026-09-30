import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/wire_time.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';

/// F06-18 — API_SPEC §1.1 은 시각을 "ISO-8601 + 오프셋" 으로 규정한다.
/// `DateTime.now()`(기기 로컬)를 그대로 `toIso8601String()` 하면 오프셋 없는
/// 문자열이 나가 서버가 거절하거나 서버 시간대로 잘못 읽는다.
void main() {
  // 오프셋(`Z` 또는 `+09:00`)으로 끝나야 한다.
  final hasOffset = matches(RegExp(r'(Z|[+-]\d{2}:\d{2})$'));
  // 기기 표준시와 무관하게 로컬 시각 객체를 만든다 — `DateTime(...)` 은 항상 로컬이다.
  final localTime = DateTime(2026, 9, 30, 8, 42, 3, 123);

  test('toWireTime 은 같은 순간을 오프셋을 붙여 낸다', () {
    final wire = toWireTime(localTime);

    expect(wire, hasOffset);
    expect(DateTime.parse(wire).isAtSameMomentAs(localTime), isTrue);
  });

  test('비상 발신의 occurred_at 은 오프셋을 싣는다', () {
    final json = EmergencyRaiseRequest(
      type: EmergencyType.values.first,
      clientKey: 'k',
      occurredAt: localTime,
    ).toJson();

    expect(json['occurred_at'], hasOffset);
  });

  test('승하차 처리의 occurred_at 은 오프셋을 싣는다', () {
    final json = BoardingUpdateRequest(
      status: RiderStatus.boarded,
      clientKey: 'k',
      occurredAt: localTime,
    ).toJson();

    expect(json['occurred_at'], hasOffset);
  });

  test('위치 송신의 recorded_at 도 오프셋을 싣는다', () {
    final json = PositionRequest(
      lat: 37.5,
      lng: 127,
      recordedAt: localTime,
    ).toJson();

    expect(json['recorded_at'], hasOffset);
  });
}
