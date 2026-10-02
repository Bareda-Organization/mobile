import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
import 'package:meta/meta.dart';

/// 마지막 승하차지 도착 처리 응답(`is_final`)을 받은 회차 id — 하원 잔류로 서버 회차가 아직 `moving`
/// 이어도 버스는 종점에 도착했으므로 위치 송신은 여기서 끝난다(R33 M1).
final StateProvider<String?> transmissionEndedRunIdProvider =
    StateProvider<String?>((ref) => null);

/// 지금 위치를 보내야 하는 회차 id — 없으면 `null`. 오늘 회차 목록에서 **내가 기사이고 운행 중**
/// (`moving`)인 회차를 직접 고르고, 종점 도착 응답을 받은 회차는 뺀다. 화면에서 고른 회차
/// (`selectedRunIdProvider`)와 무관하다 — 홈에서 다른 회차 카드를 눌러도 송신은 멈추지 않는다(F06-12).
/// 회차 목록을 다시 불러와도 같은 값이면 알리지 않으므로 송신기가 다시 만들어지지 않는다.
final Provider<String?> transmittingRunIdProvider = Provider<String?>((ref) {
  final canTransmit =
      ref.watch(roleCapabilitiesProvider)?.canTransmitPosition ?? false;
  if (!canTransmit) return null;
  final runs = ref.watch(todayRunsProvider).value;
  final picked = runs == null ? null : pickResumableRun(runs);
  final endedRunId = ref.watch(transmissionEndedRunIdProvider);
  if (picked == null || picked.runId == endedRunId) return null;
  return picked.runId;
});

/// 송신기가 마지막으로 본 값 — 운행 화면이 버스 마커·위치 안내를 그릴 때 쓴다.
@immutable
class PositionTransmission {
  const new({this.availability, this.busPosition});

  // 값이 같으면 같은 상태다 — 2초마다 같은 좌표로 상태를 다시 넣어도 화면을 다시 그리지 않게 한다(F06-17).
  @override
  bool operator ==(Object other) =>
      other is PositionTransmission &&
      other.availability == availability &&
      other.busPosition == busPosition;

  @override
  int get hashCode => Object.hash(availability, busPosition);

  /// 마지막 송신 시도에서 본 [PositionSource.availability]. 아직 한 번도 시도하지 않았으면 `null`.
  final PositionAvailability? availability;

  /// 기사 단말이 마지막으로 잰 좌표. 아직 못 쟀으면 `null` — 버스 마커를 지어내지 않는다.
  final ({double lat, double lng})? busPosition;
}

/// 앱 전역 위치 송신기(LOC-01, API_SPEC §4.12) — 화면이 아니라 운행 상태에 묶인다.
/// [transmittingRunIdProvider] 가 회차 id 를 내는 동안 위치 스트림을 켜고 2초마다
/// 좌표를 올린다. 회차가 끝나거나 로그아웃해 값이 `null` 이 되면 `build` 가 다시
/// 돌면서 앞 실행의 타이머·스트림이 먼저 멎는다 — 송신기는 항상 하나다. 앱
/// 루트(`app.dart`)가 이 provider 를 붙들어 어느 화면에서든 돈다.
class PositionTransmitter extends Notifier<PositionTransmission> {
  /// 위치 요청이 진행 중인지 — 끝나기 전에는 다음 주기가 새 요청을 열지 않는다.
  bool _sending = false;

  @override
  PositionTransmission build() {
    final runId = ref.watch(transmittingRunIdProvider);
    if (runId == null) return const PositionTransmission();
    final source = ref.read(positionSourceProvider)..start();
    // 전송 상태(`positionLinkProvider`)의 시작 시각을 송신이 시작되는 이 순간에 맞춘다 — 칩이 늦게 열려도 같다.
    ref.read(positionLinkProvider);
    _sending = false;
    final timer = Timer.periodic(
      PositionConstants.transmissionInterval,
      (_) => unawaited(_tick(runId, source)),
    );
    ref.onDispose(() {
      timer.cancel();
      source.stop();
    });
    return const PositionTransmission();
  }

  /// 주기마다 좌표를 읽어 §4.12 로 올린다. 화면 액션이 아니라 배경 텔레메트리라 실패해도 알리지 않는다 —
  /// 다음 주기 전송이 실패를 대신 만회하고, 매번 배너를 띄우면 운전 중 방해만 된다.
  Future<void> _tick(String runId, PositionSource source) async {
    // 앞 요청이 아직 끝나지 않았으면(음영 구간) 이번 주기는 건너뛴다 — 요청이 쌓였다가 복구 순간
    // 오래된 좌표까지 한꺼번에 도착하지 않게 한다(F06-07 (3)).
    if (_sending) return;
    // 권한·위치 서비스를 나중에 켜도 되살아나게 다시 확인시킨다(F06-03) — 정상이면 아무 일도 없다.
    if (source.availability != PositionAvailability.available) source.start();
    final sample = source.sample();
    state = PositionTransmission(
      availability: source.availability,
      busPosition: sample == null
          ? state.busPosition
          : (lat: sample.lat, lng: sample.lng),
    );
    if (sample == null) return;
    _sending = true;
    try {
      await ref
          .read(positionRepositoryProvider)
          .sendPosition(
            runId: runId,
            request: PositionRequest(
              lat: sample.lat,
              lng: sample.lng,
              recordedAt: sample.recordedAt,
              speed: sample.speed,
              heading: sample.heading,
            ),
          );
      // 서버가 받았다 — 운행 화면의 전송 상태 칩이 이 시각부터 센다. 그사이 송신 대상 회차가 바뀌었으면 옛 회차의 성공이다.
      if (ref.read(transmittingRunIdProvider) == runId) {
        ref.read(positionLinkProvider.notifier).markSent();
        // 서버에 닿았다 — 끊겨 재연결 대기 중인 실시간 연결이 있으면 바로 다시 붙게 알린다(R46-FIXCONN C-10).
        ref.read(serverReachedProvider.notifier).state++;
      }
    } on Failure {
      // 배경 전송 실패 — 다음 주기가 대신한다(§1.9 는 화면 액션의 낙관적 표시를 금지할 뿐이다). 실패는 조용히
      // 넘기되 마지막 성공 시각은 그대로 둬서, 운행 화면의 상태 칩이 "N초 전 마지막 전송" 으로 드러낸다(R46).
    } finally {
      _sending = false;
    }
  }
}

/// [PositionTransmitter] — 앱 전역에 하나.
final NotifierProvider<PositionTransmitter, PositionTransmission>
positionTransmitterProvider =
    NotifierProvider<PositionTransmitter, PositionTransmission>(
      PositionTransmitter.new,
    );
