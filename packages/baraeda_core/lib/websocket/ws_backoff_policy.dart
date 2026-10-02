import 'dart:math';

/// 재연결 대기 간격 정책 — 지수 백오프 + 상한 + (선택) 포기(give-up) 조건.
///
/// `stomp_dart_client` 의 `StompConfig.reconnectDelay` 는 **고정 지연 하나뿐**
/// 이다 — 내부 구현이 `Timer(config.reconnectDelay, () => _connect())` 라
/// 재시도 횟수와 무관하게 매번 같은 간격으로, 무한히 재시도한다. 그대로
/// 쓰면 서버가 죽었을 때 배터리를 계속 쓰면서 서버에도 같은 간격으로
/// 부하를 준다. 그래서 `BaraedaWebSocketClient` 는 `reconnectDelay` 를
/// `Duration.zero` 로 줘 라이브러리의 내장 재연결을 비활성화하고
/// (`stomp_handler.dart`·`stomp.dart` 양쪽 다 `reconnectDelay.inMilliseconds
/// > 0` 일 때만 재연결을 스케줄한다), 대신 이 정책이 계산한 지연으로 직접
/// `Timer` 를 건다.
///
/// 순수 계산 클래스로 둔 이유 — `Timer` 를 직접 다루면 단위 시험이 실제
/// 시간만큼 기다려야 하거나 `fake_async` 가 필요해진다. 간격 계산만
/// 분리해 두면 "3번째 재시도의 대기가 정확히 몇 ms 인가"를 `Timer` 없이
/// 바로 검사할 수 있다.
class WsBackoffPolicy {
  /// 기본값은 1·2·4·8·16·30초, 이후 30초(상한) 간격으로 **포기 없이** 계속 시도한다
  /// (R46-FIXRT S-5). 지터는 매번 붙는다.
  const new({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2,
    this.maxAttempts,
    this.jitterRatio = 0.3,
  });

  /// 1회차 재연결 대기.
  final Duration initialDelay;

  /// 대기 상한 — 계산값이 이보다 크면 이 값으로 잘린다.
  final Duration maxDelay;

  /// 회차마다 곱하는 배수.
  final num multiplier;

  /// 이 횟수를 넘기면 [shouldGiveUp] 이 `true` — 더 이상 자동 재시도하지 않는다.
  /// `null`(기본)이면 포기하지 않는다. 6회(약 1분) 뒤 포기하던 옛 기본값은 터널·음영이
  /// 1분을 넘기거나 백엔드 재기동이 길어지면(`start_period 90s`) 실시간 연결을 끊긴
  /// 채 방치해, 다른 직원의 변경을 못 받는 매니저 앱과 멈춘 위치를 보는 학부모
  /// 지도를 만들었다. 망이 죽은 동안의 비용은 30초마다 소켓 시도 1회뿐이다.
  final int? maxAttempts;

  /// [jitteredDelayFor] 가 대기를 최대 이 비율만큼 **줄이는** 폭. 0 이면 지터 없음.
  final double jitterRatio;

  /// `attempt` 는 1부터 시작(첫 재연결 시도). `initialDelay * multiplier^(attempt-1)`
  /// 을 계산하고 [maxDelay] 로 자른다.
  Duration delayFor(int attempt) {
    assert(attempt >= 1, 'attempt 는 1부터 시작한다 (첫 재연결 시도 = 1)');
    // 실수로 계산한다 — 정수 `pow(2, 64)` 는 넘쳐서 0 이 되어, 포기 없이 64회(상한 30초면 약 30분)를 넘기면
    // 대기가 0 이 돼 재연결이 쉬지 않고 도는 폭주가 된다. 실수는 무한대로 가서 상한으로 잘린다.
    final rawMs =
        initialDelay.inMilliseconds * pow(multiplier.toDouble(), attempt - 1);
    final cappedMs = min(rawMs, maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: cappedMs.round());
  }

  /// [delayFor] 에서 무작위로 최대 [jitterRatio] 만큼 줄인 대기. 서버 재배포로 모든 앱이 동시에
  /// 끊기면 고정 간격은 같은 순간에 재접속이 몰린다(서버는 1대) — 간격을 흩어 그 몰림을
  /// 푼다. 줄이는 방향으로만 더해 [maxDelay] 를 넘지 않는다.
  Duration jitteredDelayFor(int attempt, Random random) {
    final ms = delayFor(attempt).inMilliseconds;
    return Duration(
      milliseconds: (ms * (1 - random.nextDouble() * jitterRatio)).round(),
    );
  }

  /// `attempt` 번째 시도를 하기 전에 이미 포기 조건에 도달했는가 — [maxAttempts] 가
  /// `null` 이면 언제나 `false`.
  bool shouldGiveUp(int attempt) {
    final limit = maxAttempts;
    return limit != null && attempt > limit;
  }
}
