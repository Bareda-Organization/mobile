/// 바래다 공용 네트워크·에러·토큰 저장 패키지 — 앱은 이 파일 하나만 import 한다.
///
/// `apps/parent-app` · `apps/manager-app` 가 이 패키지에 의존해 dio 설정,
/// 에러 매핑, 토큰 저장을 공유한다. 구조는 `CONVENTIONS_FLUTTER.md §2` 를 따른다.
library;

export 'auth/account_role.dart';
export 'auth/account_status.dart';
export 'auth/auth_api.dart';
export 'auth/models/academy_ref.dart';
export 'auth/models/academy_summary.dart';
export 'auth/models/device_registration.dart';
export 'auth/models/login_response.dart';
export 'auth/models/me_response.dart';
export 'auth/models/reapply_response.dart';
export 'auth/models/signup_models.dart';
export 'auth/models/signup_status_response.dart';
export 'error/failure.dart';
export 'id/as_id_string.dart';
export 'network/api_client.dart';
export 'network/dio_error_mapper.dart';
export 'network/token_refresher.dart';
export 'storage/token_storage.dart';
export 'time/clock.dart';
export 'websocket/baraeda_websocket_client.dart';
export 'websocket/ws_backoff_policy.dart';
export 'websocket/ws_channel.dart';
export 'websocket/ws_connection_state.dart';
export 'websocket/ws_event_type.dart';
export 'websocket/ws_payloads.dart';
export 'websocket/websocket_envelope.dart';
