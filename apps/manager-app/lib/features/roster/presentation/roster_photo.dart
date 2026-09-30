/// 명단 행 사진 한 장을 요청하는 데 필요한 값 — 주소와(있다면) 인증 헤더.
typedef RosterPhoto = ({String url, Map<String, String>? headers});

/// §4.2 `photo_url` 을 이미지 요청 값으로 바꾼다(Ruling 377).
///
/// - `null`·빈 값 → `null` (미등록이 기본 상태라 이니셜로 그린다)
/// - 상대 경로(`/api/v1/files/photos/..`) → [baseUrl] 의 호스트에 붙이고 토큰 헤더를 싣는다.
///   경로에 `/api/v1` 이 이미 들어 있어 `baseUrl` 전체를 앞에 붙이면 두 번 붙으므로
///   `Uri.resolve` 로 호스트만 취한다. 토큰을 아직 못 읽었으면([authHeaders] `null`)
///   401 만 맞을 요청을 보내지 않고 `null` 로 둔다.
/// - 절대 URL(옛 공개 주소) → 그대로. 남의 호스트에 토큰이 새지 않게 헤더는 싣지 않는다.
RosterPhoto? resolveRosterPhoto(
  String? raw, {
  required String baseUrl,
  required Map<String, String>? authHeaders,
}) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/')) return (url: raw, headers: null);
  if (authHeaders == null) return null;
  final url = Uri.parse(baseUrl).resolve(raw).toString();
  return (url: url, headers: authHeaders);
}
