import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';

/// 서버에 닿는지 여부 — 화면 맨 위 한 줄 표시(`OfflineBar`)의 근거다(R46 B2 #22).
class NetworkStatus {
  const new({this.isOffline = false, this.lastReachableAt});

  /// 마지막 요청이 연결 실패·시간 초과로 끝났는가.
  final bool isOffline;

  /// 서버가 마지막으로 응답한 시각 — 끊긴 동안 화면의 정보가 이 시각 기준이다.
  final DateTime? lastReachableAt;
}

class NetworkStatusNotifier extends StateNotifier<NetworkStatus> {
  new({
    NetworkStatus initial = const NetworkStatus(),
    this._clock = const SystemClock(),
  }) : super(initial);

  final Clock _clock;

  /// 서버가 답했다(성공이든 4xx·5xx 든) — 연결 중이다.
  void markReachable() {
    state = NetworkStatus(lastReachableAt: _clock.now());
  }

  /// 연결 실패·시간 초과 — 마지막으로 닿은 시각은 그대로 남긴다.
  void markUnreachable() {
    if (state.isOffline) return;
    state = NetworkStatus(
      isOffline: true,
      lastReachableAt: state.lastReachableAt,
    );
  }
}

/// `connectivity_plus` 를 쓰지 않는 이유 — 기기가 와이파이에 붙어 있어도 서버에 못 닿는 경우(음영 구간·서버 중단)가
/// 있고, 그 값은 요청 결과로만 알 수 있다. 의존성도 늘리지 않는다.
final networkStatusProvider =
    StateNotifierProvider<NetworkStatusNotifier, NetworkStatus>(
      (ref) => NetworkStatusNotifier(clock: ref.watch(clockProvider)),
    );

/// 모든 REST 요청이 지나가는 Dio 에 붙여 서버 도달 여부를 [onReachable]·[onUnreachable] 로 알린다.
///
/// 서버가 4xx·5xx 로 답한 것은 서버에 닿은 것이라 끊김이 아니다. 요청 취소나 알 수 없는 오류는 판단하지 않는다.
class NetworkStatusInterceptor extends Interceptor {
  new({
    required this.onReachable,
    required this.onUnreachable,
  });

  final void Function() onReachable;
  final void Function() onUnreachable;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    onReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        onUnreachable();
      case DioExceptionType.badResponse:
        onReachable();
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        break;
    }
    handler.next(err);
  }
}
