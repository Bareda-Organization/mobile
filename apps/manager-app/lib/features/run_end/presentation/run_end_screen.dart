import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 운행 종료(C-15, 시안 `run-end` · `run-end--pending`) — 마지막 승하차지 도착 처리 직후에 열린다.
///
/// 합계(하차 · 미승차 · 미등원)는 **종료 뒤 §4.2 명단의 `counts` 를 다시 받아** 그린다(`Ruling 827`) —
/// 도착 응답의
/// 스냅샷은 하차 대기 판정에만 쓴다. 하원에서 아직 버스에 학생이 남아 있으면(`finish_pending`) 종료가 보류돼
/// 하차 대기 명단과 보호자 부재 보고 단추가 보이고, 전원이 내리면 서버가 종료한다.
class RunEndScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RunEndScreen> createState() => _RunEndScreenState();
}

class _RunEndScreenState extends ConsumerState<RunEndScreen> {
  @override
  void initState() {
    super.initState();
    // 열릴 때마다 명단을 새로 받는다 — 종료 직전의 낡은 값으로 합계를 그리지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(rosterProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    // 도착 응답 스냅샷은 그 회차의 것일 때만 쓴다 — 마지막 도착 처리가 스냅샷과 함께
    // [transmissionEndedRunIdProvider] 를 같은 회차로 채운다. 다른 회차의 종료 화면을 열면 앞 회차의
    // 도착 시각·하차 대기가 그대로 나오던 것을 막는다(F06-14).
    final snapshot = ref.watch(lastArriveResultProvider);
    final termination =
        snapshot != null && ref.watch(transmissionEndedRunIdProvider) == runId
        ? snapshot
        : null;
    final finished =
        ref.watch(selectedManagerRunProvider)?.runStatus == RunStatus.finished;
    final pending =
        termination != null && termination.finishPending && !finished;

    return Scaffold(
      appBar: ManagerHeader(title: pending ? '운행 종료 보류' : '운행 종료'),
      body: runId == null || termination == null
          ? const EmptyState(
              title: '끝난 운행이 없어요',
              body: '운행이 끝나면 여기서 결과를 볼 수 있어요.',
            )
          : pending
          ? _Pending(termination: termination)
          : const _Done(),
    );
  }
}

/// 종료 보류 — 하차 대기 학생들과 보고 단추.
class _Pending extends ConsumerWidget {
  const new({required this.termination});

  final ArriveStopResult termination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final roster = ref.watch(rosterProvider).value;
    final waiting = [
      if (roster != null)
        for (final stop in roster.stops)
          for (final student in stop.students)
            if (student.status == RiderStatus.boarded)
              (
                name: student.name,
                meta: [
                  student.className,
                  if (!student.canGoAlone) '혼자 귀가 불가',
                ].whereType<String>().join(' · '),
              ),
    ];
    final fallback = [
      for (final rider in termination.remaining) (name: rider.name, meta: ''),
    ];
    final riders = waiting.isEmpty ? fallback : waiting;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AlertBanner(
                tone: AlertTone.moving,
                title: '${hhmm(termination.arrivedAt)} 마지막 승하차지에 도착했어요',
                body: '하차 대기 ${riders.length}명 · 전원이 내려야 운행이 끝나요. 위치는 계속 보내요.',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '아직 버스에 있는 학생',
                      style: BaraedaTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '동승자가 하차 처리해요',
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              BaraedaListGroup(
                children: [
                  for (final rider in riders)
                    BaraedaListRow(
                      title: rider.name,
                      titleIsPersonName: true,
                      subtitle: rider.meta.isEmpty ? null : rider.meta,
                      trailing: const BaraedaStatusPill(
                        status: BaraedaStatus.boarded,
                        label: '탑승',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '보호자가 없어 내릴 수 없는 학생은 아래에서 보고하면 학원 관계자가 바로 알아요.',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          children: [
            BaraedaButton(
              label: '보호자 부재 보고',
              size: BaraedaButtonSize.xl,
              block: true,
              onPressed: () =>
                  unawaited(context.push(AppRoutes.reportGuardian)),
            ),
            const SizedBox(height: 8),
            BaraedaButton(
              label: '현장 상황 보고',
              variant: BaraedaButtonVariant.secondary,
              block: true,
              onPressed: () => unawaited(context.push(AppRoutes.report)),
            ),
          ],
        ),
      ],
    );
  }
}

/// 종료 완료 — 합계 3칸 · 도착 기록 · 현장 보고 · 오늘 운행으로.
class _Done extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final rosterAsync = ref.watch(rosterProvider);
    final roster = rosterAsync.value;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (rosterAsync.hasError && roster == null)
                AlertBanner(
                  tone: AlertTone.missed,
                  title: '합계를 불러오지 못했어요',
                  body: describeError(rosterAsync.error!),
                  action: BaraedaButton(
                    label: '다시 시도',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: () => ref.invalidate(rosterProvider),
                  ),
                )
              else
                BaraedaCard(
                  accent: BaraedaStatus.boarded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '운행이 끝났어요',
                        style: BaraedaTypography.h3.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (roster == null)
                        const BaraedaSkeleton(height: 48)
                      else
                        _CountsRow(roster: roster),
                    ],
                  ),
                ),
              if (roster != null) ...[
                const SizedBox(height: 24),
                Text(
                  '도착 기록',
                  style: BaraedaTypography.title.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                BaraedaCard(
                  child: StopTimeline(
                    stops: [
                      for (final stop in roster.stops) _arrivalStop(stop),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              BaraedaListGroup(
                children: [
                  BaraedaListRow(
                    leadingIcon: 'triangle-alert',
                    title: '현장 상황 보고',
                    subtitle: '도로 통제 · 차량 문제를 알려요',
                    trailing: BaraedaIcon(
                      'chevron-right',
                      color: colors.textSecondary,
                    ),
                    onTap: () => unawaited(context.push(AppRoutes.report)),
                  ),
                ],
              ),
            ],
          ),
        ),
        _BottomBar(
          children: [
            BaraedaButton(
              label: '오늘 운행으로',
              size: BaraedaButtonSize.xl,
              block: true,
              onPressed: () => context.go(AppRoutes.home),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountsRow extends StatelessWidget {
  const new({required this.roster});

  final RosterResponse roster;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cell(int value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$value', style: BaraedaTypography.h2),
                const TextSpan(text: '명', style: BaraedaTypography.body),
              ],
            ),
            style: TextStyle(color: colors.textPrimary),
          ),
          Text(
            label,
            style: BaraedaTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        // `counts.boarded` 는 지금 타고 있는 학생 수 — 종료 뒤엔 0 이라 하차는 학생 행에서 센다.
        cell(roster.alightedCount, '하차'),
        cell(roster.counts.noShow, '미승차'),
        cell(roster.counts.absentN, '미등원'),
      ],
    );
  }
}

/// 맨 아래 고정 단추 줄.
class _BottomBar extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
            children: children,
          ),
        ),
      ),
    );
  }
}

/// 도착 기록 한 줄 — 건너뛴 곳은 빨간 `미경유`, 도착한 곳은 시각.
Stop _arrivalStop(RosterStop stop) {
  if (stop.change == StopChange.skipped) {
    return Stop(
      name: stop.name,
      address: '정차 안 함',
      time: '미경유',
      state: StopState.skipped,
    );
  }
  final arrivedAt = stop.arrivedAt;
  return Stop(
    name: stop.name,
    time: arrivedAt == null ? null : hhmm(arrivedAt),
    state: arrivedAt == null ? StopState.upcoming : StopState.done,
  );
}
