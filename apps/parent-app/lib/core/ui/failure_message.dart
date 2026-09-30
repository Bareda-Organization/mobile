import 'package:baraeda_core/baraeda_core.dart';

/// 쓰기 요청이 실패했을 때 화면에 띄울 공통 문구 — 연결이 끊긴 것과 서버가 거절한 것을 가른다(F05-14).
///
/// 화면은 자기 화면만의 에러 코드(`CHANGE_LIMIT_REACHED` 등)를 먼저 처리하고, 나머지를 여기로 넘긴다.
/// [fallback] 은 서버 문구도 없는 알 수 없는 실패에 쓴다.
String failureMessage(Failure failure, {required String fallback}) =>
    switch (failure) {
      NetworkFailure() => '네트워크 상태를 확인해 주세요',
      ApiFailure(:final message) => message,
      _ => fallback,
    };

/// 임시 취소된 회차(`409 RUN_CANCELED`, Ruling 376)에 탑승 토글·변경 신청을 보냈을 때의 문구.
const String runCanceledMessage = '학원에서 임시로 취소한 회차입니다. 학원에 문의해 주세요';
