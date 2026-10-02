import 'package:baraeda_core/auth/account_status.dart';

/// `GET /auth/signup-status` 응답 (API_SPEC §2.3) — 대기 화면이 그리는 값.
class SignupStatusResponse {
  /// [rejectReason] 만 선택값(§2.3 응답 표 — `rejected` 일 때만 채워짐).
  const SignupStatusResponse({
    required this.status,
    required this.academyName,
    required this.academyRegion,
    required this.academyCode,
    required this.requestedAt,
    required this.academyContact,
    this.rejectReason,
  });

  /// 응답 본문의 `academy` 중첩 객체를 펼쳐서 옮긴다.
  factory SignupStatusResponse.fromJson(Map<String, dynamic> json) {
    final academy = json['academy'] as Map<String, dynamic>;
    return SignupStatusResponse(
      status:
          AccountStatus.fromWireValueOrNull(json['status'] as String?) ??
          AccountStatus.pending,
      academyName: academy['name'] as String,
      academyRegion: academy['region'] as String,
      academyCode: academy['code'] as String,
      requestedAt: DateTime.parse(json['requested_at'] as String),
      academyContact: json['academy_contact'] as String?,
      rejectReason: json['reject_reason'] as String?,
    );
  }

  /// `pending` · `active` · `rejected`.
  final AccountStatus status;

  /// 신청 학원명.
  final String academyName;

  /// 신청 학원 지역.
  final String academyRegion;

  /// 신청 학원 코드.
  final String academyCode;

  /// 신청 일시.
  final DateTime requestedAt;

  /// 학원 문의처 — 학원이 대표 연락처를 등록하지 않았으면 `null`(Ruling 781).
  final String? academyContact;

  /// 학원 문의처가 `null` 일 때 화면이 보이는 대체 문구 — 웹과 같다(시험이 웹 파일과 대조한다).
  static const noAcademyContactText = '등록된 문의처 없음';

  /// 화면에 그릴 문의처 — 값이 없으면 [noAcademyContactText].
  String get academyContactText => academyContact ?? noAcademyContactText;

  /// `rejected` 일 때만 채워짐.
  final String? rejectReason;
}
