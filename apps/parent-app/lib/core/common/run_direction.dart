/// 등원·하원 방향 — `home`(§3.5) · `schedule`(§3.7) 두 feature 가 함께
/// 쓰므로 `core/` 에 둔다(CONVENTIONS_FLUTTER.md §2).
enum RunDirection {
  toAcademy('to_academy'),
  fromAcademy('from_academy');

  new(this.wireValue);

  final String wireValue;

  /// 화면 표시용 한글 라벨 — 화면마다 별도 매핑을 두지 않는다.
  String get label => switch (this) {
    RunDirection.toAcademy => '등원',
    RunDirection.fromAcademy => '하원',
  };

  static RunDirection fromWireValue(String value) => switch (value) {
    'to_academy' => RunDirection.toAcademy,
    'from_academy' => RunDirection.fromAcademy,
    _ => throw ArgumentError('알 수 없는 direction: $value'),
  };
}
