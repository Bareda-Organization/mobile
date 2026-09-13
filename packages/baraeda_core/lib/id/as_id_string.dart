/// ID 필드 파싱 도우미 — `apps/parent-app/lib/core/common/json_id.dart` 의
/// 공유판. 그 파일은 REST 응답 전용으로 이미 존재했고(그 앱에만), 이 패키지가
/// 새로 소비하는 것은 WebSocket 봉투다.
///
/// `API_SPEC.md §7` 공통 봉투는 `run_id` 를 `string` 으로 문서화하지만,
/// 실제 서버 `WebSocketEnvelope`(`backend/.../global/websocket/WebSocketEnvelope.java`)
/// 는 `Long runId` 를 그대로 내보낸다 — 문서와 코드가 갈린 지점을
/// javadoc 이 REST 전체 관례에 맞춘 의도적 선택이라 밝히고 있다(Ruling 275,
/// 위반 15건 · `String`/`Long` 두 관례 공존). `payload` 안의 `student_id` ·
/// `emergency_id` · `rider_id` 도 같은 사정이다.
///
/// 이 WebSocket 봉투는 그 불일치의 **첫 소비자**다 — 여기서 직접 `as String`
/// 캐스팅을 쓰면 서버가 어느 쪽 관례를 택하든 절반은 깨진다. 실제로 이
/// 저장소에서 같은 형태의 캐스팅이 이미 두 번 앱을 죽였다(`BE-R1` 비상 화면 ·
/// `FE-R2` ②구간 탑승 변경). `parent-app`·`manager-app` 양쪽이 이 함수를
/// 거쳐서만 식별자를 읽으면 서버 쪽 관례가 바뀌어도 흡수된다.
///
/// `parent-app` 의 기존 사본은 이 패키지가 대신하지 않는다 — 그 파일은 REST
/// 응답 파싱에 남아 있는 별개 소비자이고, 이 작업의 범위는 WebSocket
/// 클라이언트뿐이다.
String asIdString(dynamic value) => value.toString();
