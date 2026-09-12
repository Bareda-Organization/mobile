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
  ApiFailure(code: 'VALIDATION_FAILED', :final message) => message,
  ApiFailure(:final message) => message,
  NetworkFailure() => '네트워크 상태를 확인해 주세요',
  UnauthenticatedFailure() => '로그인이 만료됐습니다. 다시 로그인해 주세요',
  UnknownFailure() => '요청을 처리하지 못했습니다',
};
