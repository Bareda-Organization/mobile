/// `GET /me/students` 응답 항목 (API_SPEC §3.1) — 학부모의 연결 자녀 1명.
///
/// `home`·`schedule` 두 feature 가 함께 쓰므로 `core/` 에 둔다
/// (CONVENTIONS_FLUTTER.md §2 "features 는 서로 import 하지 않는다").
class Student {
  const Student({
    required this.studentId,
    required this.name,
    required this.linkedAt,
    this.className,
  });

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    studentId: json['student_id'] as String,
    name: json['name'] as String,
    linkedAt: DateTime.parse(json['linked_at'] as String),
    className: json['class_name'] as String?,
  );

  /// 학생 식별자.
  final String studentId;

  /// 알림 문구에 필수 포함되는 이름(§3.1).
  final String name;

  /// 연결 시각.
  final DateTime linkedAt;

  /// 반 — 선택값.
  final String? className;
}
