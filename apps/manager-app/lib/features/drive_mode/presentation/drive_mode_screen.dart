import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/arrive_stop_flow.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_mode_body.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/domain/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/presentation/open_navigation.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

/// DriveMode — 운행 시작(§4.4) · 승하차지 도착 처리(§4.5), 기사 전용
/// (M-08·M-10, role_policy.dart `canOperateRun`).
///
/// 다음 처리 대상은 §4.2 명단의 `arrived_at` 로 계산한다(`drive_mode_providers.dart`
/// 참고). 가운데 지도는 `DriveMapPanel` — 노선·승하차지·버스 위치를 보인다.
/// 도착·종료 대형 버튼은 지도 아래가 아니라 화면 아래에 붙여 둔다 — 지도가 커져도 밀려나지 않는다.
class DriveModeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DriveModeScreen> createState() => _DriveModeScreenState();
}

class _DriveModeScreenState extends ConsumerState<DriveModeScreen> {
  bool _submitting = false;
  String? _errorMessage;

  /// 도착 처리에 성공한 직후 버튼을 잠그는 시간 — 신호 대기 중 더블탭이 다음 승하차지까지 처리하는 것을 막는다.
  /// 되돌리는 API 가 없어 한 번 나간 도착은 취소할 수 없다.
  static const _arriveLockDuration = Duration(seconds: 2);
  bool _arriveLocked = false;
  Timer? _arriveLockTimer;

  /// 외부 내비를 여는 중 — 겹쳐 누르지 않게 한다. 열고 나서 서버가 잘랐다고 알리면 그 안내를 [_navNotice] 에 둔다.
  bool _navigating = false;
  String? _navNotice;

  /// 카카오내비가 설치돼 있지 않다 — 안내 배너에 [설치하기] 를 붙인다.
  bool _naviNotInstalled = false;

  /// [initState] 에서 받아 둔 포트 — `ConsumerState.dispose()` 안에서는
  /// `ref.read` 가 안전하지 않다(위젯이 이미 unmount 되는 중이라 Riverpod
  /// 이 `StateError` 를 던진다). 필드에 저장해 두면 dispose 에서 이 값만
  /// 쓰면 되고 `ref` 를 다시 묻지 않는다.
  late final WakelockPort _wakelockPort;

  /// 송신기가 아직 안 도는 동안(막 열렸거나 송신이 멈췄을 때) 화면이 직접 재확인한 위치 권한·서비스 상태.
  /// 송신 중에는 송신기의 상태(`PositionTransmission.availability`)가 우선한다.
  PositionAvailability? _recheckedAvailability;
  Timer? _availabilityTimer;

  /// 기기에 저장해 둔 명단(`RosterResponse.cachedAt`)으로 다음 곳을 가리키는 동안 서버에서 다시 받아 보는
  /// 주기 — 연결이 돌아오면 서버 명단으로 바뀐다. 서버에서 받은 명단이면 아무것도 하지 않는다.
  static const _cachedRetryInterval = Duration(seconds: 15);
  Timer? _cachedRetryTimer;

  @override
  void initState() {
    super.initState();
    // 백그라운드 위치 송신은 범위 밖이라, 운행 화면이 켜져 있는
    // 것이 지금 GPS 송신을 지키는 유일한 수단이다.
    _wakelockPort = ref.read(wakelockPortProvider);
    unawaited(_wakelockPort.enable());
    _cachedRetryTimer = Timer.periodic(_cachedRetryInterval, (_) {
      if (ref.read(driveModeRosterProvider).value?.cachedAt != null) {
        ref.invalidate(driveModeRosterProvider);
      }
    });
    // 권한을 중간에 끄거나 위치 서비스가 꺼져도 주기마다 다시 본다. 스트림은 켜지 않는다.
    if (ref.read(roleCapabilitiesProvider)?.canTransmitPosition ?? false) {
      final source = ref.read(positionSourceProvider);
      unawaited(_recheck(source));
      _availabilityTimer = Timer.periodic(
        PositionConstants.transmissionInterval,
        (_) => unawaited(_recheck(source)),
      );
    }
  }

  Future<void> _recheck(PositionSource source) async {
    await source.recheck();
    if (!mounted || source.availability == _recheckedAvailability) return;
    setState(() => _recheckedAvailability = source.availability);
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _cachedRetryTimer?.cancel();
    _arriveLockTimer?.cancel();
    unawaited(_wakelockPort.disable());
    super.dispose();
  }

  /// 도착 처리 한 번 — 확인 · 요청 · 결과별 갱신은 [ArriveStopFlow] 가 하고, 화면 상태만 여기서 바꾼다.
  Future<void> _arriveStop(
    String runId,
    String stopId, {
    required String name,
    required RunDirection direction,
    bool isLast = false,
    bool hasBoardedRiders = false,
  }) =>
      ArriveStopFlow(
        context: context,
        ref: ref,
        isMounted: () => mounted,
        onBegin: () => setState(() {
          _submitting = true;
          _errorMessage = null;
        }),
        onEnd: () => setState(() => _submitting = false),
        onError: (message) => setState(() => _errorMessage = message),
        lockArriveButton: _lockArriveButton,
      ).run(
        runId,
        stopId,
        name: name,
        direction: direction,
        isLast: isLast,
        hasBoardedRiders: hasBoardedRiders,
      );

  /// 지도 위 [다음 목적지] · [남은 전 구간] 단추로 고른 범위의 길안내를 카카오내비로 연다(UF-D-02, RUN-08,
  /// Ruling 570) — 범위를 고르는 시트는 없다.
  Future<void> _openNavigation(String runId, NavigationScope scope) async {
    setState(() {
      _navigating = true;
      _errorMessage = null;
      _navNotice = null;
      _naviNotInstalled = false;
    });
    final result = await openExternalNavigation(
      ref,
      runId: runId,
      scope: scope,
    );
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _naviNotInstalled = result.notInstalled;
      _errorMessage = result.error;
      _navNotice = result.truncatedNotice;
    });
  }

  void _lockArriveButton() {
    setState(() => _arriveLocked = true);
    _arriveLockTimer?.cancel();
    _arriveLockTimer = Timer(_arriveLockDuration, () {
      if (mounted) setState(() => _arriveLocked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 저장해 둔 도착이 큐에서 빠졌다 — 서버로 나갔거나 영구 실패다. 서버의 도착 시각을 새로 받는다. 안 받으면
    // "처리한 곳" 에서 빠진 그 곳이 다음 곳으로 되살아난다(859).
    ref.listen(queuedArrivalStopIdsProvider, (previous, next) {
      if (previous == null || next.containsAll(previous)) return;
      ref
        ..invalidate(driveModeRosterProvider)
        ..invalidate(todayRunsProvider);
    });
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(driveModeRunProvider);
    final transmission = ref.watch(positionTransmitterProvider);
    final availability = transmission.availability ?? _recheckedAvailability;

    return Scaffold(
      appBar: ManagerHeader(
        title: '운행 중',
        subtitle: run == null
            ? null
            : '${run.busNo} · ${directionLabel(run.direction)} · '
                  '${hhmm(run.departTime)} 출발',
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없어요 — 운행에서 회차를 골라 주세요'))
          : DriveModeBody(
              runId: runId,
              run: run,
              transmission: transmission,
              availability: availability,
              errorMessage: _errorMessage,
              navNotice: _navNotice,
              naviNotInstalled: _naviNotInstalled,
              navigating: _navigating,
              submitting: _submitting,
              arriveLocked: _arriveLocked,
              onNavigation: (scope) => unawaited(_openNavigation(runId, scope)),
              onArrive: _arriveStop,
            ),
    );
  }
}
