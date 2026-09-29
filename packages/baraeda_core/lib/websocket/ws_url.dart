/// REST `baseUrl`(`.../api/v1`)에서 STOMP 엔드포인트 URL 을 유도한다 —
/// 스킴 교체(`https` → `wss`, 그 밖은 `ws`) + 경로를 `/ws/location` 으로 고정.
///
/// 앱 2종이 함께 쓴다. 스킴을 `ws` 로 박으면 배포 서버(`https`)에서 암호화되지
/// 않은 연결을 시도해 막히므로, 주소 조립은 이 함수 한 곳에만 둔다.
String wsUrlFromApiBaseUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
  // 쿼리·프래그먼트는 REST baseUrl 쪽 값이라 STOMP 엔드포인트에는 의미가
  // 없어 아예 뺀다 — `Uri.replace(query: '')` 는 "빈 쿼리가 있다" 로 남아
  // `?` 를 그대로 찍으므로 (`Uri.replace` 는 인자를 안 주면 원본 값을
  // 물려주고, 지우려면 새로 만드는 수밖에 없다) `Uri()` 로 새로 만든다.
  return Uri(
    scheme: wsScheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/ws/location',
  ).toString();
}
