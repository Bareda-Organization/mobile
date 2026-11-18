import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/home/domain/models/manager_run.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_screen_parts.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_stop_section.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// 받은 명단을 그리는 목록 — 알림 띠 · 처리 단추 · 집계 · 승하차지 카드들. 아래로 당겨 새로 받는다.
class RosterList extends ConsumerWidget {
  const new({
    required this.runId,
    required this.canDecide,
    required this.run,
    required this.roster,
    required this.interaction,
    super.key,
  });

  final String runId;
  final bool canDecide;
  final ManagerRun? run;
  final RosterResponse roster;
  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoHeaders = ref.watch(rosterPhotoHeadersProvider).value;
    final refreshError = ref.watch(rosterProvider).error;
    final allQueued = ref.watch(pendingRequestsProvider).value ?? const [];
    final caps = ref.watch(roleCapabilitiesProvider);
    // 서버가 5xx 를 되풀이해 재생에서 뺀 행(영구 실패)은 "전송 대기" 가 아니다 — 학생 행은 다시 누를 수 있게 두고
    // 보내지 못한 처리가 있다는 것만 따로 알린다.
    final queuedRequests = [
      for (final request in allQueued)
        if (!request.failed) request,
    ];
    final queuedRiderIds = {
      for (final request in queuedRequests) ?request.riderId,
    };

    // 머리 번호는 서버 seq 가 아니라 이 목록의 순번이다 — 서버 seq 는 경유 지점 자리(§4.3)를 비운 채 와서
    // 1·3·4 로 건너뛴다. 지도 핀 번호와 같은 규칙(`Ruling 400`).
    final stops = roster.stops;
    final currentIndex = stops.indexWhere(
      (stop) => stop.arrivedAt == null && stop.change != StopChange.skipped,
    );
    final arrivedIndexes = [
      for (final (i, stop) in stops.indexed)
        if (stop.arrivedAt != null) i,
    ];
    // 지난 곳 묶음을 펼쳤을 때만 지난 곳 카드가 먼저 나오고, 그 뒤로 아직 도착하지 않은 곳이 온다.
    final shownIndexes = [
      if (interaction.pastExpanded) ...arrivedIndexes,
      for (var i = 0; i < stops.length; i++)
        if (stops[i].arrivedAt == null) i,
    ];
    final noShowStudents = [
      for (final stop in stops)
        for (final student in stop.students)
          if (student.status == RiderStatus.noShow &&
              student.noShowCase != null)
            student,
    ];
    final readOnly = interaction.readOnly;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(rosterProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _RosterNotices(
            runId: runId,
            run: run,
            cachedAt: roster.cachedAt,
            refreshError: refreshError,
          ),
          _RosterActionBar(
            readOnly: readOnly,
            canSendDelay: caps?.canSendDelayNotification ?? false,
            canOpenQueue: caps?.canDecideBoardingStatus ?? false,
            queuedTotal: allQueued.length,
          ),
          const SizedBox(height: 12),
          if (!readOnly && noShowStudents.isNotEmpty) ...[
            NoShowWaitBanner(
              student: noShowStudents.first,
              onContact: () =>
                  interaction.onOpenNoShow(noShowStudents.first.riderId),
            ),
            const SizedBox(height: 12),
          ],
          RosterStatsCard(
            counts: roster.counts,
            boardedLabel: roster.direction == RunDirection.fromAcademy
                ? '탑승 중'
                : '탑승',
          ),
          const SizedBox(height: 12),
          _RosterQueueNotices(
            errorMessage: interaction.errorMessage,
            queuedCount: queuedRequests.length,
            failedCount: allQueued.length - queuedRequests.length,
          ),
          if (!readOnly &&
              canDecide &&
              roster.direction == RunDirection.fromAcademy)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '처리할 학생이 위에, 끝난 학생이 아래에 있어요.',
                style: BaraedaTypography.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          if (arrivedIndexes.isNotEmpty) ...[
            PastStopsCard(
              stops: [for (final i in arrivedIndexes) stops[i]],
              expanded: interaction.pastExpanded,
              onToggle: interaction.onTogglePast,
            ),
            const SizedBox(height: 12),
          ],
          for (final i in shownIndexes)
            RosterStopSection(
              runId: runId,
              stop: stops[i],
              order: i + 1,
              isCurrent: i == currentIndex,
              direction: roster.direction,
              canDecide: canDecide,
              photoHeaders: photoHeaders,
              queuedRiderIds: queuedRiderIds,
              interaction: interaction,
            ),
        ],
      ),
    );
  }
}

/// 목록 맨 위 안내 — 저장된 명단 · 갱신 실패 · 변경 확인 띠.
class _RosterNotices extends ConsumerWidget {
  const new({
    required this.runId,
    required this.run,
    required this.cachedAt,
    required this.refreshError,
  });

  final String runId;
  final ManagerRun? run;
  final DateTime? cachedAt;
  final Object? refreshError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cachedAt case final receivedAt?) ...[
          AlertBanner(
            tone: AlertTone.info,
            icon: 'wifi-off',
            title: '저장된 명단을 보고 있어요',
            body: '${hhmm(receivedAt)} 에 받은 명단이에요 · 연결되면 자동으로 새로 받아요',
          ),
          const SizedBox(height: 12),
        ],
        if (refreshError case final error?) ...[
          AlertBanner(
            tone: AlertTone.missed,
            title: '최신 명단을 불러오지 못했어요',
            body: '이전 명단을 보고 있어요 · ${describeError(error)}',
            action: BaraedaButton(
              label: '다시 시도',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: () => ref.invalidate(rosterProvider),
            ),
          ),
          const SizedBox(height: 12),
        ],
        ChangeAckBanner(
          runId: runId,
          ackRequired: run?.ackRequired ?? false,
          addedCount: run?.addedCount ?? 0,
          removedCount: run?.removedCount ?? 0,
          bottomGap: 12,
        ),
      ],
    );
  }
}

/// 처리 단추 줄 — 조회 전용이면 안내 띠, 아니면 지연 알림 · 예외 보고 · 대기열.
class _RosterActionBar extends StatelessWidget {
  const new({
    required this.readOnly,
    required this.canSendDelay,
    required this.canOpenQueue,
    required this.queuedTotal,
  });

  final bool readOnly;
  final bool canSendDelay;
  final bool canOpenQueue;
  final int queuedTotal;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return const AlertBanner(
        tone: AlertTone.info,
        icon: 'eye',
        body: '기사는 명단을 볼 수만 있어요. 승차 · 하차 처리는 동승자가 해요.',
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // UF-E-05 "명단 → [지연 알림]" — M-05 는 **동승자 전용**(기사는 운전 중).
        if (canSendDelay)
          BaraedaButton(
            label: '지연 알림',
            size: BaraedaButtonSize.sm,
            icon: 'clock',
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(context.push(AppRoutes.delay)),
          ),
        // 예외 보고(M-14) — 보호자 부재·도로 통제 등. 기사는 운행 화면의 종료 보고서로,
        // 동승자는 여기서 보고한다.
        BaraedaButton(
          label: '예외 보고',
          size: BaraedaButtonSize.sm,
          icon: 'triangle-alert',
          variant: BaraedaButtonVariant.secondary,
          onPressed: () => unawaited(context.push(AppRoutes.report)),
        ),
        // ⚠ 오프라인 큐는 **이 화면에서만** 갈 수 있어야 한다(M-06 · UF-E-07) — 도달 불가면
        // 통신 두절로
        // 쌓인 승하차 처리가 **영영 안 나간다**. 승하차를 처리하는 주체(동승자)에게 연다.
        if (canOpenQueue)
          BaraedaButton(
            label: queuedTotal == 0 ? '대기열' : '대기열 $queuedTotal건',
            icon: 'inbox',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(context.push(AppRoutes.offlineQueue)),
          ),
      ],
    );
  }
}

/// 통계 아래 안내 — 처리 실패 오류 · 대기열에 쌓인 처리 · 보내지 못한 처리.
class _RosterQueueNotices extends StatelessWidget {
  const new({
    required this.errorMessage,
    required this.queuedCount,
    required this.failedCount,
  });

  final String? errorMessage;
  final int queuedCount;
  final int failedCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: errorMessage),
          const SizedBox(height: 12),
        ],
        if (queuedCount > 0) ...[
          // 큐에 쌓인 처리가 있는 동안은 다음 조작이 이 안내를 지우지 않는다 — 큐가 비면 사라진다.
          AlertBanner(
            tone: AlertTone.moving,
            body: '처리되지 않았어요 · 대기 중 $queuedCount건',
          ),
          const SizedBox(height: 12),
        ],
        if (failedCount > 0) ...[
          AlertBanner(
            tone: AlertTone.missed,
            body: '서버가 계속 받지 못해 보내지 못한 처리 $failedCount건 · 대기열에서 확인하세요',
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
