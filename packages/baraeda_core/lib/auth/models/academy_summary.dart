/// `GET /academies/search` 결과 한 건 (API_SPEC §2.1).
///
/// 코드 생성 없이 손으로 `fromJson` 을 쓴다 — 이 패키지는 freezed 만 이미
/// 쓰고 있고(§ `error/failure.dart`), 평평한 DTO 하나 때문에
/// `json_serializable` 빌드 러너를 추가로 얹지 않는다(§ 판단 근거는
/// 보고서에 남긴다).
class AcademySummary {
  /// 필드 4개 전부 서버가 항상 채워 보낸다(§2.1 응답 표에 선택값 없음).
  const new({
    required this.id,
    required this.name,
    required this.region,
    required this.code,
  });

  /// `items[]` 배열의 원소 하나를 그대로 옮긴다.
  factory fromJson(Map<String, dynamic> json) => AcademySummary(
    id: json['id'] as String,
    name: json['name'] as String,
    region: json['region'] as String,
    code: json['code'] as String,
  );

  /// 가입 요청 시 그대로 전달하는 학원 내부 식별자.
  final String id;

  /// 학원명.
  final String name;

  /// 동명 학원 구분값(지역).
  final String region;

  /// 서버 자동 생성 학원 코드.
  final String code;

  /// 선택 화면 표기 규칙(§2.1) — `{학원명} · {지역} · {학원 코드}`.
  String get displayLabel => '$name · $region · $code';
}
