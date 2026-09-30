import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';

/// 마지막 승하차지 도착 처리 응답(`is_final`)을 받은 회차 id — 하원 잔류로 서버 회차가 아직 `moving`
/// 이어도 버스는 종점에 도착했으므로 위치 송신은 여기서 끝난다(R33 M1).
final StateProvider<String?> transmissionEndedRunIdProvider =
    StateProvider<String?>((ref) => null);

/// 지금 위치를 보내야 하는 회차 id — 없으면 `null`. 운행 중(`moving`)인 **기사** 회차이고 종점 도착
/// 응답을 받지 않았을 때만 값이 있다. 역할·선택 회차·회차 상태가 바뀌어야 값이 바뀌므로
/// (같은 값은 알리지 않는다) 회차 목록을 다시 불러와도 송신기가 다시 만들어지지 않는다.
final Provider<String?> transmittingRunIdProvider = Provider<String?>((ref) {
  final canTransmit =
      ref.watch(roleCapabilitiesProvider)?.canTransmitPosition ?? false;
  final runId = ref.watch(selectedRunIdProvider);
  final run = ref.watch(driveModeRunProvider);
  final endedRunId = ref.watch(transmissionEndedRunIdProvider);
  if (!canTransmit || runId == null || runId == endedRunId) return null;
  return run?.runStatus == RunStatus.moving ? runId : null;
});

/// 송신기가 마지막으로 본 값 — 운행 화면이 버스 마커·위치 안내를 그릴 때 쓴다.
class PositionTransmission {
  const PositionTransmission({this.availability, this.busPosition});

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
  @override
  PositionTransmission build() {
    final runId = ref.watch(transmittingRunIdProvider);
    if (runId == null) return const PositionTransmission();
    final source = ref.read(positionSourceProvider)..start();
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
    } on Failure {
      // 배경 전송 실패 — 다음 주기가 대신한다(§1.9 는 화면 액션의 낙관적 표시를 금지할 뿐이다).
    }
  }
}

/// [PositionTransmitter] — 앱 전역에 하나.
final NotifierProvider<PositionTransmitter, PositionTransmission>
positionTransmitterProvider =
    NotifierProvider<PositionTransmitter, PositionTransmission>(
      PositionTransmitter.new,
    );
