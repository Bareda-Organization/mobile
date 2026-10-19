/// 자녀 연결 2종 응답 (API_SPEC §3.3·§3.4, Ruling 324). 화면 진입점의 기능 ID 는
/// `FEATURE_SPEC.md §5.1` 색인 기준 **P-02**(자녀 연결·인증 코드) 다 — P-01 은 가입·로그인.
/// 이 파일·화면의 주석도 P-02 로 적는다.
library;

import 'package:parent_app/core/common/json_id.dart';

/// §3.3 — 학생이 생성한 인증 코드. 선행 조건이 없다(Ruling 324).
class LinkCodeResult {
  const new({required this.code, required this.expiresAt});

  factory fromJson(Map<String, dynamic> json) => LinkCodeResult(
    code: json['code'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final String code;
  final DateTime expiresAt;
}

/// §3.4 — 코드 인증으로 연결 완료된 자녀.
class LinkConfirmResult {
  const new({required this.studentId, required this.name});

  factory fromJson(Map<String, dynamic> json) =>
      LinkConfirmResult(
        studentId: asIdString(json['student_id']),
        name: json['name'] as String,
      );

  final String studentId;
  final String name;
}
