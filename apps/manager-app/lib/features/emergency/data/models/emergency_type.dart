/// §4.14 `type` — 4종. `etc` 는 `memo` 가 필수(그 외는 선택).
enum EmergencyType {
  accident('accident'),
  vehicleFault('vehicle_fault'),
  studentEmergency('student_emergency'),
  etc('etc');

  new(this.wireValue);

  final String wireValue;

  static EmergencyType? fromWireValueOrNull(String? value) {
    for (final type in EmergencyType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }

  /// 화면에 보여줄 한국어 라벨 — presentation 이 이 enum 을 직접 들고
  /// 있으니 라벨도 여기 한 곳에서만 정의한다(여러 화면에서 같은 매핑을
  /// 반복하지 않기 위함).
  String get label => switch (this) {
    EmergencyType.accident => '사고',
    EmergencyType.vehicleFault => '차량 고장',
    EmergencyType.studentEmergency => '학생 응급',
    EmergencyType.etc => '기타',
  };
}
