/// 로그인·`/me` 응답에 실리는 축약 학원 정보 (`id`·`name` 뿐).
/// 가입 화면의 검색 결과(`AcademySummary`, §2.1)와는 필드가 달라 구분한다.
class AcademyRef {
  /// [id]·[name] 둘 다 필수 — 서버가 `academy` 를 내려줄 때는 항상 이 둘을
  /// 채워서 보낸다(`system_admin` 은 `academy` 자체가 `null`).
  const AcademyRef({required this.id, required this.name});

  /// 응답 JSON 의 `academy` 객체를 그대로 옮긴다.
  factory AcademyRef.fromJson(Map<String, dynamic> json) =>
      AcademyRef(id: json['id'] as String, name: json['name'] as String);

  /// 학원 내부 식별자.
  final String id;

  /// 학원명.
  final String name;
}
