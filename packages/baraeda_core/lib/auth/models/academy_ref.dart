/// 로그인·`/me` 응답에 실리는 축약 학원 정보 (`id`·`name`·`contact`).
/// 가입 화면의 검색 결과(`AcademySummary`, §2.1)와는 필드가 달라 구분한다.
class AcademyRef {
  /// [id]·[name] 둘 다 필수 — 서버가 `academy` 를 내려줄 때는 항상 이 둘을
  /// 채워서 보낸다(`system_admin` 은 `academy` 자체가 `null`).
  const new({required this.id, required this.name, this.contact});

  /// 응답 JSON 의 `academy` 객체를 그대로 옮긴다.
  factory fromJson(Map<String, dynamic> json) => AcademyRef(
    id: json['id'] as String,
    name: json['name'] as String,
    contact: json['contact'] as String?,
  );

  /// 학원 내부 식별자.
  final String id;

  /// 학원명.
  final String name;

  /// 학원 대표 연락처 — 학원이 등록하지 않았으면 `null`. 매니저 앱이 통신 두절 때 학원에 전화를 거는 번호다
  /// (R46-MGR, API_SPEC §2.5·§2.10).
  final String? contact;
}
