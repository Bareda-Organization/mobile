/// 자녀 연결 2종 응답 (API_SPEC §3.3·§3.4, Ruling 324). 화면 진입점은 BRIEF 상
/// "P-01·S-05" 로 적혀 있으나 `FEATURE_SPEC.md §5.1` 색인의 정본 기준
/// 기능 ID 는 **P-02**(자녀 연결·인증 코드) 다 — P-01 은 가입·로그인.
/// 이 파일·화면의 주석은 정본 기준 P-02 로 적는다(보고서 §2 참고).
library;

import 'package:parent_app/core/common/json_id.dart';

/// §3.3 — 학생이 생성한 인증 코드. 선행 조건이 없다(Ruling 324).
class LinkCodeResult {
  const LinkCodeResult({required this.code, required this.expiresAt});

  factory LinkCodeResult.fromJson(Map<String, dynamic> json) =>
      LinkCodeResult(
        code: json['code'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String code;
  final DateTime expiresAt;
}

/// §3.4 — 코드 인증으로 연결 완료된 자녀.
class LinkConfirmResult {
  const LinkConfirmResult({required this.studentId, required this.name});

  factory LinkConfirmResult.fromJson(Map<String, dynamic> json) =>
      LinkConfirmResult(
        studentId: asIdString(json['student_id']),
        name: json['name'] as String,
      );

  final String studentId;
  final String name;
}
