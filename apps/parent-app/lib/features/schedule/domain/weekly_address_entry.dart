import 'package:parent_app/core/common/run_direction.dart';

/// `GET`·`PATCH /students/{id}/weekly-address` 항목 (API_SPEC §3.7).
///
/// **기본 주소 개념이 부재** (C-12) — 요일 × 방향 조합마다 별도 주소를
/// 갖는다.
enum Weekday {
  mon,
  tue,
  wed,
  thu,
  fri,
  sat,
  sun;

  static Weekday fromWireValue(String value) => switch (value) {
    'mon' => Weekday.mon,
    'tue' => Weekday.tue,
    'wed' => Weekday.wed,
    'thu' => Weekday.thu,
    'fri' => Weekday.fri,
    'sat' => Weekday.sat,
    'sun' => Weekday.sun,
    _ => throw ArgumentError('알 수 없는 weekday: $value'),
  };

  String get wireValue => name;

  /// 화면 표기 — `월`·`화`·... (CONVENTIONS_FLUTTER.md 카피 규칙, 요일은
  /// 한 글자로 축약해 세그먼트 컨트롤에 쓴다).
  String get label => switch (this) {
    Weekday.mon => '월',
    Weekday.tue => '화',
    Weekday.wed => '수',
    Weekday.thu => '목',
    Weekday.fri => '금',
    Weekday.sat => '토',
    Weekday.sun => '일',
  };
}

class WeeklyAddressEntry {
  const new({
    required this.weekday,
    required this.direction,
    required this.address,
    this.addressDetail,
    this.lat,
    this.lng,
    this.verified,
  });

  factory fromJson(Map<String, dynamic> json) =>
      WeeklyAddressEntry(
        weekday: Weekday.fromWireValue(json['weekday'] as String),
        direction: RunDirection.fromWireValue(json['direction'] as String),
        address: json['address'] as String,
        addressDetail: json['address_detail'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        verified: json['verified'] as bool?,
      );

  Map<String, dynamic> toJson() => {
    'weekday': weekday.wireValue,
    'direction': direction.wireValue,
    'address': address,
    if (addressDetail != null) 'address_detail': addressDetail,
  };

  final Weekday weekday;
  final RunDirection direction;
  final String address;

  /// 아파트 동·출입구 등 상세 위치.
  final String? addressDetail;

  /// 서버 응답에만 존재(요청에는 없음) — 주소 검증 결과.
  final double? lat;
  final double? lng;
  final bool? verified;

  WeeklyAddressEntry copyWith({String? address, String? addressDetail}) =>
      WeeklyAddressEntry(
        weekday: weekday,
        direction: direction,
        address: address ?? this.address,
        addressDetail: addressDetail ?? this.addressDetail,
        lat: lat,
        lng: lng,
        verified: verified,
      );
}
