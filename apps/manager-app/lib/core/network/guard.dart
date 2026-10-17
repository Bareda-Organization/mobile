import 'package:baraeda_core/baraeda_core.dart';

/// 서버에 닿지 못한 실패 — 연결 두절 · 서버 5xx ·
/// 게이트웨이(nginx · Cloudflare Tunnel)의 HTML 오류 페이지.
/// 마지막으로 알던 값(저장 요약)으로 버틸 수 있다. HTML 오류 페이지는 JSON 이 아니라 `UnknownFailure` 로 오고
/// (`statusCode` 가 그 상태 — 응답이 없었으면 `null`), 서버 프로세스가 죽었을 때 정확히 이 모양이다.
/// 저장 요약 폴백 전용이다 — 응답 없는 `UnknownFailure`(statusCode null)도 두절로 보지만,
/// 오프라인 대기열은 같은 경우를 두절로 보지 않고(재전송을 쌓지 않으려고) 명단 저장소는 5xx 만 두절로 보므로
/// 이 정의를 그쪽에 재사용하지 않는다.
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

/// 이 실패로 로그인 세션이 끝난다 — 재발급이 거절된 인증 실패(401)와 대기·거절 게이트(`403 AUTH_PENDING` ·
/// `AUTH_REJECTED`). 그 밖의 403(권한)이나 4xx 는 세션을 끝내지 않으므로 해당하지 않는다.
bool isSessionEndingFailure(Failure failure) =>
    failure is UnauthenticatedFailure ||
    (failure is ApiFailure &&
        (failure.statusCode == 401 ||
            (failure.statusCode == 403 &&
                (failure.code == 'AUTH_PENDING' ||
                    failure.code == 'AUTH_REJECTED'))));
