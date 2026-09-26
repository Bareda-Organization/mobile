import 'package:baraeda_core/baraeda_core.dart';

/// [Failure] → 화면에 보여줄 한 줄 문구. `login_screen.dart` 의 스위치를
/// 4개 화면(DriveMode·StopRoster·DelayScreen·RunEndScreen)이 반복하지
/// 않도록 공용화했다 — 로그인 화면 고유의 `INVALID_CREDENTIALS`·
/// `AUTH_ACCOUNT_BLOCKED` 분기는 옮기지 않는다(그 둘은 로그인에만 있다).
String describeFailure(Failure failure) => switch (failure) {
  ApiFailure(code: 'START_WINDOW_CLOSED') => '운행 시작 가능 시간(출발 ±10분)이 아닙니다',
  ApiFailure(code: 'RUN_ALREADY_STARTED') => '이미 시작된 운행입니다',
  ApiFailure(code: 'RUN_NOT_CONFIRMED') => '아직 확정되지 않은 운행입니다',
  ApiFailure(code: 'RUN_NOT_MOVING') => '운행 중 상태가 아닙니다',
  ApiFailure(code: 'DUPLICATE_ARRIVE') => '이미 도착 처리된 승하차지입니다',
  ApiFailure(code: 'DRIVER_ONLY') => '버스기사만 처리할 수 있습니다',
  ApiFailure(code: 'ESCORT_ONLY') => '동승자만 처리할 수 있습니다',
  ApiFailure(code: 'DELAY_DUPLICATE') => '직전과 같은 지연 알림은 다시 보낼 수 없습니다',
  // M3(Ruling 345) — 같은 상태 재요청 포함, 전이표 밖 요청. 명단 재조회는
  // roster_screen.dart 의 호출부가 이 코드를 보고 별도로 트리거한다(이
  // 함수는 문구만 옮긴다).
  ApiFailure(code: 'RIDER_TRANSITION_NOT_ALLOWED') =>
    '이미 처리된 학생입니다 — 명단을 새로 불러왔습니다',
  // M4(Ruling 340) — 취소된 회차. 서버 문구 그대로가 이미 맞아 텍스트는
  // 바꾸지 않지만, 다른 코드처럼 이 표에 명시해 둔다(목록 재조회는
  // drive_mode_screen.dart 호출부가 트리거).
  ApiFailure(code: 'RUN_CANCELED') => '취소된 회차입니다',
  // §4.15 403 은 배치되지 않은 회차·타 학원 회차·존재하지 않는 회차 세
  // 경우를 한 코드로 묶는다(2026-09-09 문면 정정, Ruling 259(b)) — 회차
  // 존재 여부를 코드로 구별하면 배치되지 않은 매니저에게 그 회차가
  // 있다는 사실 자체가 새어 나간다. 그래서 이 문구도 하나만 둔다.
  ApiFailure(code: 'FORBIDDEN') => '이 회차를 이용할 권한이 없습니다',
  ApiFailure(code: 'EMERGENCY_CANCEL_WINDOW_CLOSED') =>
    '비상 알림 취소 가능 시간(발신 후 1분)이 지났습니다',
  ApiFailure(code: 'EMERGENCY_NOT_FOUND') => '비상 알림을 찾을 수 없습니다',
  ApiFailure(code: 'VALIDATION_FAILED', :final message) => message,
  ApiFailure(:final message) => message,
  NetworkFailure() => '네트워크 상태를 확인해 주세요',
  UnauthenticatedFailure() => '로그인이 만료됐습니다. 다시 로그인해 주세요',
  UnknownFailure() => '요청을 처리하지 못했습니다',
};
