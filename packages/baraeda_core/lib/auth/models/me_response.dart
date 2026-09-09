import 'package:baraeda_core/auth/account_role.dart';
import 'package:baraeda_core/auth/account_status.dart';
import 'package:baraeda_core/auth/models/academy_ref.dart';

/// `GET /me` 응답 (API_SPEC §2.10) — 자동 로그인·계정 상태 재취득에 쓴다.
class MeResponse {
  /// [academy]·[studentId]·[managerId]·[managerRole]·[linkedStudentCount] 는
  /// 전부 역할별 선택값(§2.10 응답 표 참고).
  const MeResponse({
    required this.accountId,
    required this.loginId,
    required this.name,
    required this.phone,
    required this.role,
    required this.status,
    this.academy,
    this.studentId,
    this.managerId,
    this.managerRole,
    this.linkedStudentCount,
  });

  /// 응답 본문을 그대로 옮긴다.
  factory MeResponse.fromJson(Map<String, dynamic> json) {
    final academyJson = json['academy'] as Map<String, dynamic>?;
    return MeResponse(
      accountId: json['account_id'] as String,
      loginId: json['login_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      role: AccountRole.fromWireValueOrNull(json['role'] as String?),
      status: AccountStatus.fromWireValueOrNull(json['status'] as String?),
      academy: academyJson == null ? null : AcademyRef.fromJson(academyJson),
      studentId: json['student_id'] as String?,
      managerId: json['manager_id'] as String?,
      managerRole: json['manager_role'] as String?,
      linkedStudentCount: json['linked_student_count'] as int?,
    );
  }

  /// 계정 식별자.
  final String accountId;

  /// 로그인 아이디.
  final String loginId;

  /// 이름.
  final String name;

  /// 연락처.
  final String phone;

  /// `null` 이면 이 앱이 모르는 역할.
  final AccountRole? role;

  /// `pending` · `active` · `rejected`.
  final AccountStatus? status;

  /// `system_admin` 은 `null`.
  final AcademyRef? academy;

  /// `role=student` 일 때 본인 학생 레코드.
  final String? studentId;

  /// `role=driver`·`escort` 일 때 배정된 매니저(호차) 식별자.
  final String? managerId;

  /// `role=driver`·`escort` 일 때 배정된 매니저 역할.
  final String? managerRole;

  /// `role=parent` 일 때 연결 자녀 수.
  final int? linkedStudentCount;
}
