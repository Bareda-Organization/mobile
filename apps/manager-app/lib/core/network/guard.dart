import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';

/// `DioException` → `Failure` 변환을 반복하지 않으려고 뺀 공용 함수
/// (`AuthRepositoryImpl._guard` 와 같은 패턴 — 이번 라운드에 새로 생기는
/// repository 5개가 전부 이 변환만 반복하므로 여기 하나로 모은다).
/// `presentation` 은 이 함수를 거친 [Failure] 만 본다(CONVENTIONS_FLUTTER.md §6).
Future<T> guardDio<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (exception) {
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고).
    // ignore: only_throw_errors
    throw mapDioExceptionToFailure(exception);
  }
}

/// 서버에 닿지 못한 실패 — 연결 두절 · 서버 5xx · 게이트웨이(nginx · Cloudflare Tunnel)의 HTML 오류 페이지.
/// 마지막으로 알던 값(저장 요약)으로 버틸 수 있다. HTML 오류 페이지는 JSON 이 아니라 `UnknownFailure` 로 오고
/// (`statusCode` 가 그 상태 — 응답이 없었으면 `null`), 서버 프로세스가 죽었을 때 정확히 이 모양이다.
bool isUnreachableFailure(Failure failure) => switch (failure) {
  NetworkFailure() => true,
  ApiFailure(:final statusCode) => statusCode >= 500,
  UnknownFailure(:final statusCode) => statusCode == null || statusCode >= 500,
  UnauthenticatedFailure() => false,
};

/// 서버가 **이 계정을 거절했다는 긍정 증거** — 인증 거절(401 · 재발급 실패)과 서버가 JSON 으로 준 계정 상태
/// 거절(403). 세션을 끝내고 기기에 남긴 역할 · 요약 · 대기열을 지워도 되는 경우는 이것뿐이다.
/// 그 밖의 모든 실패(연결 두절 · 5xx · HTML 오류 페이지 · 취소 · 파싱 실패 · 그 밖 4xx)는 세션과 저장분을
/// 그대로 두고 다음 기회에 다시 확인한다.
bool isServerRejection(Failure failure) =>
    failure is UnauthenticatedFailure ||
    (failure is ApiFailure &&
        (failure.statusCode == 401 || failure.statusCode == 403));
