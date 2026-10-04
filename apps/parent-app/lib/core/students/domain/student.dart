import 'package:parent_app/core/common/json_id.dart';

/// `GET /me/students` 응답 항목 (API_SPEC §3.1) — 학부모의 연결 자녀 1명.
///
/// `home`·`schedule` 두 feature 가 함께 쓰므로 `core/` 에 둔다
/// (CONVENTIONS_FLUTTER.md §2 "features 는 서로 import 하지 않는다").
class Student {
  const new({
    required this.studentId,
    required this.name,
    required this.linkedAt,
    this.className,
    this.grade,
  });

  factory fromJson(Map<String, dynamic> json) => Student(
    studentId: asIdString(json['student_id']),
    name: json['name'] as String,
    linkedAt: DateTime.parse(json['linked_at'] as String),
    className: json['class_name'] as String?,
    grade: json['grade'] as String?,
  );

  /// 학생 식별자.
  final String studentId;

  /// 알림 문구에 필수 포함되는 이름(§3.1).
  final String name;

  /// 연결 시각.
  final DateTime linkedAt;

  /// 반 — 선택값.
  final String? className;

  /// 학년("초5") — 선택값(`Ruling 824`). 서버가 아직 안 주면 `null` 이고 화면은 그 줄을 숨긴다.
  final String? grade;
}
