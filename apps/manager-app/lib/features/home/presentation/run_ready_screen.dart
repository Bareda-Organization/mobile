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
import 'package:manager_app/core/map/route_map_view.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/ui/map_legend.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/presentation/open_navigation.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 운행 준비(기사, `Ruling 799` · `USER_FLOWS` UF-D-03) — 시작 전에 확정 노선 · 승하차지 · 학생
/// 수를 확인하고
/// [운행 시작] 을 누른다. 홈의 `운행 준비하기` 가 여기로 오고, **운행 시작 요청은 이 화면의 확인 창 뒤에만 나간다.**
///
/// [운행 시작] 은 시작 가능 시간(출발 ±10분, §4.4)이 아니거나 노선을 못 받았으면 꺼져 있고 그 이유가 단추 아래에
/// 보인다(M20). 노선 변경 확인 띠는 홈과 같은 [ChangeAckBanner] 다. 성공하면 운행 화면으로 바꿔 간다.
class RunReadyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RunReadyScreen> createState() => _RunReadyScreenState();
}

class _RunReadyScreenState extends ConsumerState<RunReadyScreen> {
  bool _starting = false;
  String? _startError;

  bool _navigating = false;
  String? _navNotice;
  bool _naviNotInstalled = false;

  /// 시작 전(송신기가 아직 안 도는 동안) 화면이 직접 재확인한 위치 권한·서비스 상태(M2-02).
  PositionAvailability? _availability;
  Timer? _availabilityTimer;

  /// 시작 가능 시각 판정을 새로 하려고 주기적으로 다시 그린다.
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // 출발 뒤에야 송신 실패를 알지 않게, 시작 전에도 권한·서비스를 주기마다 다시 본다. 스트림은 켜지 않는다.
    if (ref.read(roleCapabilitiesProvider)?.canTransmitPosition ?? false) {
      final source = ref.read(positionSourceProvider);
      unawaited(_recheck(source));
      _availabilityTimer = Timer.periodic(
        PositionConstants.transmissionInterval,
        (_) => unawaited(_recheck(source)),
      );
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _recheck(PositionSource source) async {
    await source.recheck();
    if (!mounted || source.availability == _availability) return;
    setState(() => _availability = source.availability);
  }

  Future<void> _start(String runId) async {
    // 시작하면 노선이 잠기고 학부모·관계자에게 알림이 나간다 — 되돌릴 수 없어 한 번 묻는다(R32 M6).
    // 하원은 시작과 함께 전원이 자동으로 승차 처리된다(C-07) — 그 사실을 알린다. 등원에는 해당 없다.
    final isFromAcademy =
        ref.read(driveModeRunProvider)?.direction == RunDirection.fromAcademy;
    final confirmed = await confirmAction(
      context,
      title: '운행을 시작할까요?',
      body: [
        '시작하면 학부모·관계자에게 운행 시작 알림이 나가고 노선이 잠겨요.',
        if (isFromAcademy) '학생은 하원 시작과 함께 자동으로 승차 처리되고 학부모에게 승차 알림이 가요.',
      ].join('\n'),
      confirmLabel: '시작하기',
      cancelLabel: '닫기',
    );
    if (!confirmed || !mounted) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      await ref.read(driveModeRepositoryProvider).startRun(runId);
      // 요청 중에 화면이 닫혀도 서버는 이미 시작을 반영했다 — 컨테이너로 갱신한다(F06-16).
      container
        ..invalidate(todayRunsProvider)
        ..invalidate(driveModeRosterProvider);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.driveMode);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _startError = describeFailure(failure));
      // M4(Ruling 340) — 취소된 회차는 §4.1 목록에서 빠져야 한다.
      if (failure case ApiFailure(code: 'RUN_CANCELED')) {
        container.invalidate(todayRunsProvider);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openNavigation(String runId) async {
    setState(() {
      _navigating = true;
      _navNotice = null;
      _naviNotInstalled = false;
    });
    final result = await openExternalNavigation(
      ref,
      runId: runId,
      scope: NavigationScope.remaining,
    );
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _naviNotInstalled = result.notInstalled;
      _navNotice = result.error ?? result.truncatedNotice;
    });
  }

  void _retry() {
    ref
      ..invalidate(routeProvider)
      ..invalidate(driveModeRosterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(driveModeRunProvider);
    final subtitle = run == null
        ? null
        : '${run.busNo} · ${directionLabel(run.direction)} · '
              '${hhmm(run.departTime)} 출발';

    return Scaffold(
      appBar: ManagerHeader(title: '운행 준비', subtitle: subtitle),
      body: runId == null || run == null
          ? const EmptyState(title: '선택된 운행이 없어요', body: '오늘 운행에서 회차를 골라 주세요.')
          : _buildBody(context, runId, run),
    );
  }

  Widget _buildBody(BuildContext context, String runId, ManagerRun run) {
    final routeAsync = ref.watch(routeProvider);
    final rosterAsync = ref.watch(driveModeRosterProvider);
    final route = routeAsync.value;
    final roster = rosterAsync.value;
    final failed =
        (routeAsync.hasError && route == null) ||
        (rosterAsync.hasError && roster == null);
    final loading = !failed && (route == null || roster == null);
    final colors = context.colors;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              ChangeAckBanner(
                runId: runId,
                ackRequired: run.ackRequired,
                addedCount: run.addedCount,
                removedCount: run.removedCount,
                bottomGap: 12,
              ),
              if (_positionGuidance(_availability) case final guidance?) ...[
                AlertBanner(
                  tone: AlertTone.missed,
                  body: guidance,
                  action: BaraedaButton(
                    label: '설정 열기',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: () => unawaited(
                      ref.read(settingsOpenerProvider)(
                        _availability == PositionAvailability.permissionDenied
                            ? DeviceSettingsPage.app
                            : DeviceSettingsPage.location,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (failed)
                ..._failure(colors)
              else if (loading)
                const _ReadySkeleton()
              else ...[
                _MapCard(route: route!, onExpand: () => _openRouteMap(context)),
                const SizedBox(height: 12),
                BaraedaButton(
                  label: '카카오내비로 길 확인',
                  icon: 'navigation',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                  onPressed:
                      _navigating || ref.watch(kakaoNaviAppKeyProvider).isEmpty
                      ? null
                      : () => unawaited(_openNavigation(runId)),
                ),
                if (_naviNotInstalled) ...[
                  const SizedBox(height: 8),
                  AlertBanner(
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
                ],
                if (_navNotice != null) ...[
                  const SizedBox(height: 8),
                  AlertBanner(tone: AlertTone.info, body: _navNotice),
                ],
                const SizedBox(height: 8),
                // 운행을 시작하기 전에도 승하차지 명단을 볼 수 있다(UF-D-02 · 조회 전용).
                BaraedaButton(
                  label: '명단 보기',
                  icon: 'list',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                  onPressed: () =>
                      unawaited(context.push(AppRoutes.rosterView)),
                ),
                const SizedBox(height: 24),
                _StopsSection(run: run, roster: roster!),
              ],
            ],
          ),
        ),
        _StartBar(
          run: run,
          now: ref.watch(clockProvider).now(),
          routeReady: !failed && !loading,
          starting: _starting,
          error: _startError,
          onStart: () => unawaited(_start(runId)),
          onResume: () => context.pushReplacement(AppRoutes.driveMode),
        ),
      ],
    );
  }

  List<Widget> _failure(BaraedaColors colors) => [
    const AlertBanner(
      tone: AlertTone.missed,
      icon: 'wifi-off',
      title: '확정 노선을 불러오지 못했어요',
      body: '인터넷 연결을 확인해 주세요. 노선을 받아야 운행을 시작할 수 있어요.',
    ),
    const SizedBox(height: 12),
    BaraedaButton(
      label: '다시 시도',
      icon: 'refresh',
      block: true,
      onPressed: _retry,
    ),
    const SizedBox(height: 12),
    const AcademyCallCard(lead: '출발 시각이 가까우면'),
  ];

  void _openRouteMap(BuildContext context) =>
      unawaited(context.push(AppRoutes.routeMap));

  String? _positionGuidance(PositionAvailability? availability) =>
      switch (availability) {
        PositionAvailability.permissionDenied =>
          '위치 권한이 없어 위치를 보낼 수 없어요. 설정에서 위치 권한을 허용해 주세요.',
        PositionAvailability.serviceDisabled =>
          '기기 위치 서비스가 꺼져 있어 위치를 보낼 수 없어요. 설정에서 위치 서비스를 켜 주세요.',
        PositionAvailability.available || null => null,
      };
}

/// 지도 카드 — `확정 노선` 꼬리표 · 크게 보기 단추 · 아래 범례. 지도 위 글자는 늘 잉크색(다크 구역 밖에서도 같다).
class _MapCard extends StatelessWidget {
  const new({required this.route, required this.onExpand});

  final RouteResponse route;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final legend = BaraedaTypography.caption.copyWith(
      color: colors.textSecondary,
    );
    return BaraedaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(BaraedaRadius.card),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: route.stops.isEmpty
                        ? ColoredBox(
                            color: colors.surfaceSunken,
                            child: const Center(
                              child: WordWrapText('표시할 승하차지가 없어요'),
                            ),
                          )
                        : RouteMapView(route: route),
                  ),
                  const Positioned(
                    left: 8,
                    top: 8,
                    child: BaraedaMapTag(label: '확정 노선', live: false),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: BaraedaMapButton(
                      icon: 'map',
                      semanticLabel: '노선 크게 보기',
                      onPressed: onExpand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                MapLegendItem(
                  swatch: MapLegendSwatch(color: colors.accentPrimary),
                  label: '오늘 추가',
                  style: legend,
                ),
                MapLegendItem(
                  swatch: MapLegendSwatch(
                    color: colors.statusMissed,
                    ring: true,
                  ),
                  label: '정차 안 함',
                  style: legend,
                ),
                MapLegendItem(
                  swatch: MapLegendSwatch(color: colors.textPrimary),
                  label: '지나갈 곳',
                  style: legend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "승하차지 6곳 · 학생 14명 · 미등원 2명" + 번호 타임라인(추가 · 미경유 표시).
///
/// 숫자는 명단을 세지 않고 홈 카드와 같은 회차 필드(`stopCount` · `riderCount` · `absentCount`,
/// `Ruling 822`)로 그린다 — 명단에는 등원의 도착지(학원 행)와 버스 간 이동으로 빠진 행이 섞여
/// 홈 카드와 어긋난다. 필드가 없으면(확정 전) 그 숫자를 지어내지 않고 숨긴다.
class _StopsSection extends StatelessWidget {
  const new({required this.run, required this.roster});

  final ManagerRun run;
  final RosterResponse roster;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stops = run.stopCount;
    final riders = run.riderCount;
    final absent = run.absentCount;
    final caption = [
      if (riders != null) '학생 $riders명',
      if (absent != null) '미등원 $absent명',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stops == null ? '승하차지' : '승하차지 $stops곳',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (caption.isNotEmpty)
              Text(
                caption,
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
              for (final stop in roster.stops)
                switch (stop.change) {
                  StopChange.skipped => Stop(
                    name: stop.name,
                    address: '오늘 탑승 학생 없음',
                    time: '미경유',
                    state: StopState.skipped,
                  ),
                  StopChange.added => Stop(
                    name: stop.name,
                    address: '학생 ${stop.students.length}명 · 신규',
                    time: '추가',
                    state: StopState.added,
                  ),
                  null => Stop(
                    name: stop.name,
                    address: '학생 ${stop.students.length}명',
                  ),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// 받는 중 — 지도 · 단추 · 목록 자리를 뼈대로 잡는다.
class _ReadySkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      BaraedaSkeleton(height: 240, radius: 16),
      SizedBox(height: 12),
      BaraedaSkeleton(height: 48, radius: 12),
      SizedBox(height: 24),
      BaraedaSkeletonList(),
    ],
  );
}

/// 맨 아래 고정 줄 — 주 단추 `운행 시작` + 그 아래 시작 가능 시간 · 꺼진 이유.
class _StartBar extends StatelessWidget {
  const new({
    required this.run,
    required this.now,
    required this.routeReady,
    required this.starting,
    required this.error,
    required this.onStart,
    required this.onResume,
  });

  final ManagerRun run;
  final DateTime now;
  final bool routeReady;
  final bool starting;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final moving = run.runStatus == RunStatus.moving;
    final before = now.isBefore(run.startWindowFrom);
    final after = now.isAfter(run.startWindowTo);
    final inWindow = !before && !after;

    String? reason;
    if (!moving) {
      if (!routeReady) {
        reason = '노선을 받으면 시작할 수 있어요';
      } else if (before) {
        final minutes = run.startWindowFrom.difference(now).inMinutes + 1;
        reason =
            '${hhmm(run.startWindowFrom)} 부터 시작할 수 있어요 (출발 ±10분) · $minutes분 뒤';
      } else if (after) {
        reason = '운행 시작 가능 시간(출발 ±10분)이 지났어요';
      }
    }
    final enabled = moving || (reason == null && !starting);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgBase,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                AlertBanner(tone: AlertTone.missed, body: error),
                const SizedBox(height: 8),
              ],
              BaraedaButton(
                label: moving ? '운행 화면으로' : '운행 시작',
                icon: 'bus',
                size: BaraedaButtonSize.xl,
                block: true,
                onPressed: enabled ? (moving ? onResume : onStart) : null,
                disabledReason: enabled ? null : reason,
              ),
              if (enabled && !moving && inWindow)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '시작 가능 ${hhmm(run.startWindowFrom)} ~ '
                    '${hhmm(run.startWindowTo)} (출발 ±10분)',
                    textAlign: TextAlign.center,
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
