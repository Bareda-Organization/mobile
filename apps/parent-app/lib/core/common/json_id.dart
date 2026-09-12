/// ID 필드 파싱 도우미.
///
/// `API_SPEC.md` 는 `run_id` · `stop_id` · `change_request_id` ·
/// `notification_id` · `link_request_id` 를 전부 `string` 으로 문서화하지만
/// (§3.5 · §3.8 · §3.9 · §3.12 · §3.2), 실제 서버(포트 8082 · 8080 양쪽
/// 확인)는 이 필드들을 **따옴표 없는 JSON 정수**로 돌려준다. `student_id`
/// 도 예외가 아니다 — `GET /me/students` 응답에서는 문자열("1")인데
/// `GET /notifications` 응답에서는 같은 필드가 정수(1)로 나온다(같은
/// 이름의 필드가 엔드포인트마다 다른 타입). 서버가 사양대로 문자열을
/// 보내기 시작해도, 지금처럼 정수를 보내도 양쪽 다 깨지지 않도록 이
/// 함수를 거쳐 `String` 으로 통일한다.
///
/// 이것은 클라이언트 결함의 수정이 아니라 **서버가 자신의 사양을 어기는
/// 상태를 흡수하는 임시 방편**이다 — 서버 쪽 수정이 정본 해결책이다.
String asIdString(dynamic value) => value.toString();
