import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/bottom_notice_stack.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/presentation/open_navigation.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

/// DriveMode — 운행 시작(§4.4) · 승하차지 도착 처리(§4.5), 기사 전용
/// (M-08·M-10, role_policy.dart `canOperateRun`).
///
/// 다음 처리 대상은 §4.2 명단의 `arrived_at` 로 계산한다(`drive_mode_providers.dart`
/// 참고). 가운데 지도(R32 M1)는 [DriveMapPanel] — 노선·승하차지·버스 위치를 보인다.
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
  /// 되돌리는 API 가 없어 한 번 나간 도착은 취소할 수 없다(R46).
  static const _arriveLockDuration = Duration(seconds: 2);

  /// 토스트가 도착 처리 단추 줄 위에 뜨는 높이 — 위 여백 12 + 단추 64 + 아래 여백 12 + 간격 8.
  static const _toastAboveActionBar = 96.0;
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

  /// 송신기가 아직 안 도는 동안(막 열렸거나 송신이 멈췄을 때) 화면이 직접 재확인한 위치 권한·서비스 상태(M2-02).
  /// 송신 중에는 송신기의 상태(`PositionTransmission.availability`)가 우선한다.
  PositionAvailability? _recheckedAvailability;
  Timer? _availabilityTimer;

  /// 위치 송신 상태의 [PositionAvailability] 를 화면 문구로 옮긴다 — 정상(`available`)이거나
  /// 아직 모르면(`null`) 아무것도 보여주지 않는다.
  String? _positionGuidance(PositionAvailability? availability) =>
      switch (availability) {
        PositionAvailability.permissionDenied => '위치 권한이 꺼져 있어요',
        PositionAvailability.serviceDisabled => '기기 위치 서비스가 꺼져 있어요',
        PositionAvailability.available || null => null,
      };

  String? _positionGuidanceBody(PositionAvailability? availability) =>
      availability == null || availability == PositionAvailability.available
      ? null
      : '학부모 화면에 버스 위치가 안 보여요.';

  @override
  void initState() {
    super.initState();
    // F2 — 백그라운드 위치 송신은 범위 밖이라, 운행 화면이 켜져 있는
    // 것이 지금 GPS 송신을 지키는 유일한 수단이다(M-B 2항).
    _wakelockPort = ref.read(wakelockPortProvider);
    unawaited(_wakelockPort.enable());
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
    _arriveLockTimer?.cancel();
    unawaited(_wakelockPort.disable());
    super.dispose();
  }

  Future<void> _arriveStop(
    String runId,
    String stopId, {
    required int order,
    required String name,
    bool isLast = false,
  }) async {
    // 마지막 승하차지의 도착 처리는 곧 운행 종료다(C-15) — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    // 그 앞 승하차지는 운전 중에 자주 누르는 조작이라 묻지 않는다.
    if (isLast) {
      final confirmed = await confirmAction(
        context,
        title: '마지막 승하차지예요',
        body:
            '도착 처리가 곧 운행 종료예요. 되돌릴 수 없어요.\n'
            '· 등원 학생 전원이 자동으로 하차 처리돼요\n'
            '· 위치 보내기가 멈춰요\n'
            '· 학원 관계자에게 운행 종료가 전달돼요',
        confirmLabel: '도착했어요 · 운행 종료',
        cancelLabel: '닫기',
      );
      if (!confirmed || !mounted) return;
    }
    final container = ProviderScope.containerOf(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(driveModeRepositoryProvider)
          .arriveStop(runId: runId, stopId: stopId);
      // 요청 중에 화면이 닫혀도 서버는 이미 도착을 반영했다 — 화면 생존과 무관한 갱신은 컨테이너로 한다
      // (닫힌 화면의 `ref` 는 쓸 수 없다, F06-16).
      container.invalidate(todayRunsProvider);
      if (result.isFinal) {
        // 종점에 닿았으니 위치 송신은 여기서 끝난다 — 하원 잔류로 서버 회차가 아직 `moving` 이어도 그렇다.
        container.read(transmissionEndedRunIdProvider.notifier).state = runId;
        container.read(lastArriveResultProvider.notifier).state = result;
        if (!mounted) return;
        unawaited(context.push(AppRoutes.runEnd));
      } else {
        container.invalidate(driveModeRosterProvider);
        if (!mounted) return;
        // 같은 자리 단추의 이름만 다음 승하차지로 바뀌면 처리된 줄 모른다 — 처리 사실을 토스트로 알린다(M6).
        // 시각은 서버가 적은 도착 시각(§4.5 `arrived_at`)이다.
        _lockArriveButton();
        showBaraedaToast(
          context,
          message: '$name 도착 처리했어요 · ${hhmm(result.arrivedAt)}',
          aboveTabBar: false,
          // 도착 처리 단추 줄(여백 + 단추 64 + 여백) 바로 위 — 토스트가 단추를 가리면 다음 누름을 가로챈다.
          bottomOffset: _toastAboveActionBar,
        );
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// `내비 열기` — 범위를 고르는 시트를 띄우고 고른 범위로 카카오내비를 연다(UF-D-02, RUN-08, Ruling 570).
  Future<void> _chooseNavigation(
    String runId, {
    required String nextLabel,
  }) async {
    final scope = await showBaraedaBottomSheet<NavigationScope>(
      context: context,
      title: '카카오내비로 열기',
      builder: (sheetContext) => NavigationScopeSheet(nextLabel: nextLabel),
    );
    if (scope == null || !mounted) return;
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
          : _buildBody(context, runId, run, transmission, availability),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String runId,
    ManagerRun? run,
    PositionTransmission transmission,
    PositionAvailability? availability,
  ) {
    final rosterAsync = ref.watch(driveModeRosterProvider);
    final colors = context.colors;
    // 지도 높이는 화면 비율로 정한다 — 작은 화면(360×640)에서도 아래 대형 버튼이 밀리지 않는다.
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.28).clamp(
      DriveMapPanel.minHeight,
      DriveMapPanel.maxHeight,
    );
    final roster = rosterAsync.value;
    final moving = run?.runStatus == RunStatus.moving;
    final nextStop = roster == null ? null : nextUnarrivedStop(roster);
    final navigationEnabled =
        _canUseExternalNavigation(run) && !_navigating && nextStop != null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 위치가 서버에 닿고 있는지 — 음영 구간에서 기사가 먼저 알게 한다(R46). 송신 중일 때만 그린다.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    BaraedaStatusPill(
                      status: moving
                          ? BaraedaStatus.moving
                          : BaraedaStatus.idle,
                      label: moving ? '운행 중' : '운행 전',
                      size: BaraedaStatusPillSize.lg,
                    ),
                    if (_positionGuidance(availability) != null)
                      const BaraedaStatusPill(
                        status: BaraedaStatus.missed,
                        label: '전송 안 됨',
                        size: BaraedaStatusPillSize.lg,
                      )
                    else
                      const PositionLinkChip(),
                  ],
                ),
                const SizedBox(height: 12),
                const PositionLostBanner(),
                // rosterAsync.when(...) 의 모든 분기 바깥 — "명단 없음"(정상)과
                // "연결 끊김"(비정상)을 구별해야 한다(목표 9, ManagerChannelBanner
                // 문서 참고).
                ManagerChannelBanner(runId: runId),
                // 알림은 가장 중요한 한 건만 보이고 나머지는 접힌다 — 노선 변경 확인은 접히지 않는 맨 위
                // 칸(Ruling 596).
                BottomNoticeStack(
                  leading: (run?.ackRequired ?? false)
                      ? ChangeAckBanner(
                          runId: runId,
                          ackRequired: true,
                          addedCount: run?.addedCount ?? 0,
                          removedCount: run?.removedCount ?? 0,
                        )
                      : null,
                  notices: _notices(rosterAsync, availability),
                ),
                if (run != null && roster != null && moving) ...[
                  if (nextStop != null) ...[
                    const SizedBox(height: 4),
                    _NextStopCard(
                      stop: nextStop,
                      order: _orderOf(roster, nextStop),
                      isLast: isLastRemainingStop(roster, nextStop),
                      onRoster: () =>
                          unawaited(context.push(AppRoutes.rosterView)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _mapWithControls(
                    context,
                    mapHeight,
                    transmission,
                    navigationLabel: navigationEnabled || _navigating
                        ? '내비 열기'
                        : null,
                    onNavigation: navigationEnabled
                        ? () => unawaited(
                            _chooseNavigation(
                              runId,
                              nextLabel:
                                  '${_orderOf(roster, nextStop)} '
                                  '${nextStop.name} 1곳',
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _RemainingStops(roster: roster, colors: colors),
                ] else ...[
                  const SizedBox(height: 12),
                  _mapWithControls(context, mapHeight, transmission),
                ],
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bgBase,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: rosterAsync.when(
                // 갱신이 실패해도 마지막으로 받은 명단을 지우지 않는다 — 음영 구간을 지난 직후에
                // [도착 처리] 가 사라지면 다음 실시간 이벤트가 올 때까지 기사가 조작할 수 없다(R46).
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const SizedBox.shrink(),
                data: (roster) => _buildActionArea(runId, run, roster),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 지도 + 왼쪽 위 `내비 열기` · 오른쪽 아래 `크게 보기`(노선 지도 화면, `Ruling 829`).
  Widget _mapWithControls(
    BuildContext context,
    double height,
    PositionTransmission transmission, {
    String? navigationLabel,
    VoidCallback? onNavigation,
  }) {
    return Stack(
      children: [
        DriveMapPanel(height: height, busPosition: transmission.busPosition),
        if (navigationLabel != null)
          Positioned(
            left: 8,
            top: 8,
            child: BaraedaMapButton(
              icon: 'navigation',
              label: navigationLabel,
              semanticLabel: '카카오내비',
              onPressed: onNavigation,
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: BaraedaMapButton(
            icon: 'map',
            semanticLabel: '노선 크게 보기',
            onPressed: () => unawaited(context.push(AppRoutes.routeMap)),
          ),
        ),
      ],
    );
  }

  /// 명단 안에서 이 승하차지의 번호 — 서버 `seq` 가 아니라 명단 순서(경유 지점은 명단에 없다, `Ruling 398`).
  int _orderOf(RosterResponse roster, RosterStop stop) =>
      roster.stops.indexWhere((s) => s.stopId == stop.stopId) + 1;

  /// 알림을 중요한 순서로 모은다 — 접힌 상태에서는 첫 건만 보인다([BottomNoticeStack]).
  /// 도착 처리 실패 > 명단 조회 실패 > 위치 송신 불가 > 카카오내비 미설치 > 길안내 안내 순이다:
  /// 지금 조작이 막힌 것을 앞에, 알려 주는 것을 뒤에 둔다.
  List<BottomNotice> _notices(
    AsyncValue<RosterResponse> rosterAsync,
    PositionAvailability? availability,
  ) {
    final guidance = _positionGuidance(availability);
    return [
      if (_errorMessage != null)
        BottomNotice(tone: AlertTone.missed, body: _errorMessage!),
      if (rosterAsync.hasError)
        _rosterFailureNotice(rosterAsync.error!, stale: rosterAsync.hasValue),
      if (guidance != null)
        BottomNotice(
          tone: AlertTone.missed,
          body: '$guidance ${_positionGuidanceBody(availability)}',
          action: BaraedaButton(
            label: '설정 열기',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(settingsOpenerProvider)(
                availability == PositionAvailability.permissionDenied
                    ? DeviceSettingsPage.app
                    : DeviceSettingsPage.location,
              ),
            ),
          ),
        ),
      if (_naviNotInstalled)
        BottomNotice(
          tone: AlertTone.missed,
          body: '카카오내비가 설치돼 있지 않아요. 설치한 뒤 다시 눌러 주세요.',
          action: BaraedaButton(
            label: '설치하기',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(uriOpenerProvider)(
                ref.read(kakaoNaviLauncherProvider).installUri,
              ),
            ),
          ),
        ),
      if (_navNotice != null)
        BottomNotice(tone: AlertTone.moving, body: _navNotice!),
    ];
  }

  bool _canUseExternalNavigation(ManagerRun? run) =>
      ref.watch(kakaoNaviAppKeyProvider).isNotEmpty &&
      (ref.watch(roleCapabilitiesProvider)?.canOperateRun ?? false) &&
      (run?.runStatus == RunStatus.confirmed ||
          run?.runStatus == RunStatus.moving);

  /// 명단 조회 실패 안내 + [다시 시도]. [stale] 이면 화면의 명단이 마지막 성공분이라는 뜻이다.
  BottomNotice _rosterFailureNotice(Object error, {required bool stale}) =>
      BottomNotice(
        tone: AlertTone.missed,
        body: stale
            ? '최신 명단을 불러오지 못했어요 · 이전 명단을 보고 있어요: ${describeError(error)}'
            : '명단을 불러오지 못했어요: ${describeError(error)}',
        action: BaraedaButton(
          label: '다시 시도',
          size: BaraedaButtonSize.sm,
          variant: BaraedaButtonVariant.secondary,
          onPressed: () => ref.invalidate(driveModeRosterProvider),
        ),
      );

  Widget _buildActionArea(
    String runId,
    ManagerRun? run,
    RosterResponse roster,
  ) {
    if (run == null) return const SizedBox.shrink();

    // 운행 시작은 운행 준비 화면에서만 한다(`Ruling 799`) — 아직 시작 전 회차로 들어왔으면 그리로 보낸다.
    if (run.runStatus == RunStatus.idle ||
        run.runStatus == RunStatus.confirmed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordWrapText('아직 운행을 시작하지 않았어요'),
          const SizedBox(height: 8),
          BaraedaButton(
            label: '운행 준비하기',
            icon: 'bus',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () => context.pushReplacement(AppRoutes.runReady),
          ),
        ],
      );
    }

    if (run.runStatus == RunStatus.moving) {
      final nextStop = nextUnarrivedStop(roster);
      if (nextStop == null) {
        return const WordWrapText('모든 승하차지 도착 처리가 끝났어요');
      }
      final lost = judgePositionLink(
        now: ref.read(clockProvider).now(),
        link: ref.read(positionLinkProvider),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 이름이 길어도 동사(`도착 처리`)는 잘리지 않는다 — 이름만 `…` 로 줄어든다(M5).
          BaraedaButton(
            name: nextStop.name,
            label: '도착 처리',
            icon: 'check',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: _submitting || _arriveLocked
                ? null
                : () => _arriveStop(
                    runId,
                    nextStop.stopId,
                    order: _orderOf(roster, nextStop),
                    name: nextStop.name,
                    isLast: isLastRemainingStop(roster, nextStop),
                  ),
          ),
          if (lost?.kind == PositionLinkKind.lost)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '연결이 없어도 도착 처리는 저장돼요. 연결되면 자동으로 보내요.',
                textAlign: TextAlign.center,
                style: BaraedaTypography.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WordWrapText('이미 종료된 운행이에요'),
        const SizedBox(height: 8),
        BaraedaButton(
          label: '종료 보고서 보기',
          size: BaraedaButtonSize.xl,
          block: true,
          onPressed: () => unawaited(context.push(AppRoutes.runEnd)),
        ),
      ],
    );
  }
}

/// 다음 승하차지 큰 카드 — `다음 승하차지 · 3번` + 이름(나눔명조 큰 글자) + 부제 + `명단 ›`(조회 전용 명단).
class _NextStopCard extends StatelessWidget {
  const new({
    required this.stop,
    required this.order,
    required this.isLast,
    required this.onRoster,
  });

  final RosterStop stop;
  final int order;
  final bool isLast;
  final VoidCallback onRoster;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = isLast
        ? '도착하면 운행이 끝나요'
        : [
            if (stop.change == StopChange.added) '신규',
            '탑승 예정 ${stop.students.length}명',
          ].join(' · ');
    return BaraedaCard(
      accent: BaraedaStatus.moving,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isLast ? '마지막' : '다음'} 승하차지 · $order번',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaraedaTypography.h2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          BaraedaButton(
            label: '명단',
            iconEnd: 'chevron-right',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: onRoster,
          ),
        ],
      ),
    );
  }
}

/// `남은 승하차지 3곳 · 미경유 1곳은 건너뛰어요` + 번호 타임라인 — 조회 전용(승하차 처리는 동승자만, M-12).
class _RemainingStops extends StatelessWidget {
  const new({required this.roster, required this.colors});

  final RosterResponse roster;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    final remaining = [
      for (final stop in roster.stops)
        if (stop.arrivedAt == null) stop,
    ];
    if (remaining.isEmpty) return const SizedBox.shrink();
    final skipped = remaining
        .where((stop) => stop.change == StopChange.skipped)
        .length;
    final active = remaining.length - skipped;
    final firstActive = remaining.indexWhere(
      (stop) => stop.change != StopChange.skipped,
    );
    return Column(
      key: const Key('remaining-stops'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '남은 승하차지 $active곳',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (skipped > 0)
              Text(
                '미경유 $skipped곳은 건너뛰어요',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        BaraedaCard(
          child: StopTimeline(
            stops: [
              for (var i = 0; i < remaining.length; i++)
                switch (remaining[i].change) {
                  StopChange.skipped => Stop(
                    name: remaining[i].name,
                    address: '정차 안 함',
                    time: '미경유',
                    state: StopState.skipped,
                  ),
                  _ => Stop(
                    name: remaining[i].name,
                    address: i == remaining.length - 1
                        ? '도착하면 운행이 끝나요'
                        : '학생 ${remaining[i].students.length}명'
                              '${_addedSuffix(remaining[i])}',
                    time: remaining[i].change == StopChange.added ? '추가' : null,
                    state: i == firstActive
                        ? StopState.current
                        : StopState.upcoming,
                  ),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// `내비 열기` 시트 — 다음 목적지 1곳 / 남은 전 구간(카카오내비 경유지 상한까지, Ruling 570).
class NavigationScopeSheet extends StatelessWidget {
  const new({required this.nextLabel, super.key});

  /// `3 새솔초 정문 1곳` — 다음 목적지를 눌렀을 때 넘어가는 곳.
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaListGroup(
          children: [
            BaraedaListRow(
              title: '다음 목적지',
              subtitle: nextLabel,
              trailing: BaraedaIcon(
                'chevron-right',
                color: colors.textSecondary,
              ),
              onTap: () => Navigator.of(context).pop(NavigationScope.next),
            ),
            BaraedaListRow(
              title: '남은 전 구간',
              subtitle: '앞 4곳까지 넘겨요',
              trailing: BaraedaIcon(
                'chevron-right',
                color: colors.textSecondary,
              ),
              onTap: () => Navigator.of(context).pop(NavigationScope.remaining),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '카카오내비는 경유지를 4곳까지 받아요. 남은 곳이 더 많으면 앞쪽만 넘기고 '
          '알려 드려요. 앱이 없으면 설치 화면으로 이동해요.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 신규로 추가된 승하차지의 부제 꼬리.
String _addedSuffix(RosterStop stop) =>
    stop.change == StopChange.added ? ' · 신규' : '';
