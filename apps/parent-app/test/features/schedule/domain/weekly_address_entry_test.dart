import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';

/// §3.7 파싱·직렬화 시험 — 특히 C-12(기본 주소 개념 부재)를 반영해
/// `toJson` 이 요일×방향 조합 각각을 그대로 왕복시키는지 확인한다.
void main() {
  test('WeeklyAddressEntry.fromJson 은 검증 결과 필드까지 읽는다', () {
    final entry = WeeklyAddressEntry.fromJson({
      'weekday': 'mon',
      'direction': 'to_academy',
      'address': '서울시 강남구 1',
      'address_detail': '101동 1001호',
      'lat': 37.5,
      'lng': 127.0,
      'verified': true,
    });

    expect(entry.weekday, Weekday.mon);
    expect(entry.direction, RunDirection.toAcademy);
    expect(entry.address, '서울시 강남구 1');
    expect(entry.lat, 37.5);
    expect(entry.verified, isTrue);
  });

  test('WeeklyAddressEntry.toJson 은 검증 결과 필드를 보내지 않는다', () {
    const entry = WeeklyAddressEntry(
      weekday: Weekday.tue,
      direction: RunDirection.fromAcademy,
      address: '서울시 서초구 2',
      lat: 37.4,
      lng: 127.1,
      verified: true,
    );

    final json = entry.toJson();

    expect(json['weekday'], 'tue');
    expect(json['direction'], 'from_academy');
    expect(json.containsKey('lat'), isFalse);
    expect(json.containsKey('verified'), isFalse);
  });

  test('Weekday.fromWireValue 는 알 수 없는 요일에 예외를 던진다', () {
    expect(() => Weekday.fromWireValue('wednesday'), throwsArgumentError);
  });

  test('copyWith 는 주소만 바꾸고 요일·방향은 유지한다 (C-12: 편집 전용)', () {
    const original = WeeklyAddressEntry(
      weekday: Weekday.wed,
      direction: RunDirection.toAcademy,
      address: '옛 주소',
    );

    final updated = original.copyWith(address: '새 주소');

    expect(updated.weekday, Weekday.wed);
    expect(updated.direction, RunDirection.toAcademy);
    expect(updated.address, '새 주소');
  });
}
