import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/manager_connection.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_actions.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';
import 'package:manager_app/features/roster/presentation/widgets/revert_confirm_sheet.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// 명단(§4.2 M-03 · §4.6 M-12 · §4.7 M-13 · §4.8 M-14 · §4.11 M-04 변경 확인).
///
/// 동승자는 이 화면이 아래 탭 첫 칸이고 승하차를 처리한다([readOnly] 가 `false`). 기사는 운행 화면의 `명단 ›` 로
/// 열어 보기만 한다([readOnly] — 시안 `roster-driver`, 승차 · 하차는 동승자가 한다). 지금 곳(다음 도착)은 늘
/// 펼쳐 있고 그 밖의 곳은 접혀 있어 눌러 펼친다(동승자가 직접 펼칠 수 있다). 지난 곳은 한 줄로 묶는다.
///
/// 처리 단추는 `canDecideBoardingStatus`(동승자 전용, role_policy.dart)로만 노출된다. 변경 확인 띠는
/// [ChangeAckBanner] 가 맡는다(§4.1 `ack_required` — 운행 화면도 같은 띠를 쓴다, R32 M4).
class RosterScreen extends ConsumerStatefulWidget {
  const new({super.key, this.readOnly = false});

  /// 기사의 조회 전용 열람 — 처리 단추 · 지연 알림 · 대기열이 없고 뒤로 가기가 있다.
  final bool readOnly;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  /// 응답을 기다리는 학생들 — 한 명이 아니라 집합이다. 여러 학생을 연달아 눌러도 앞 학생의 잠금이 풀리지 않는다(R46).
  final Set<String> _pendingRiderIds = {};
  String? _errorMessage;

  /// 사용자가 직접 펼친 승하차지 · 지난 곳 묶음을 펼쳤는가.
  final Set<String> _expandedStopIds = {};
  bool _pastExpanded = false;

  /// [미승차]는 [탑승] 옆에 있어 잘못 눌리기 쉽고, 처리하면 학부모에게 알림이 나간다 — 한 번
  /// 묻는다(R32 M7). 취소하면 요청을 보내지 않는다.
  Future<void> _confirmNoShow({
    required String runId,
    required String riderId,
    required String name,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: '$name 학생을 미승차로 처리할까요?',
      body: '처리하면 학부모·관계자에게 바로 알림이 나가고 연락 대기 시간이 시작돼요.',
      confirmLabel: '미승차 처리',
      cancelLabel: '닫기',
    );
    if (!confirmed || !mounted) return;
    await _updateStatus(
      runId: runId,
      riderId: riderId,
      status: RiderStatus.noShow,
    );
  }

  Future<void> _updateStatus({
    required String runId,
    required String riderId,
    required RiderStatus status,
  }) async {
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    try {
      // 즉시 전송과 재생(큐 재시도) 양쪽이 같은 client_key 를 쓰도록 여기서
      // 한 번만 만든다 — repository 가 재생 시 새로 만들지 않고 이 값을
      // 그대로 들고 있는다(payload 에 실려 drift 에 저장되므로).
      final outcome = await ref
          .read(rosterRepositoryProvider)
          .updateRiderStatus(
            runId: runId,
            riderId: riderId,
            request: BoardingUpdateRequest(
              status: status,
              clientKey: IdempotencyKeys.generate(),
              // 누른 시각 — 오프라인 재생분이 서버에 도착한 시각으로 기록되지 않게 한다(F06-05).
              occurredAt: ref.read(clockProvider).now(),
            ),
          );
      if (!mounted) return;
      switch (outcome) {
        case Sent():
          ref
            ..invalidate(rosterProvider)
            ..invalidate(pendingRequestsProvider);
        case Queued():
          // 서버에 아직 반영되지 않았으니 명단을 다시 불러오지 않는다 —
          // §1.9 낙관적 표시 금지와 같은 이유. 대기 안내·행 표시는 큐 목록에서 그린다(R46).
          ref.invalidate(pendingRequestsProvider);
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
      // M3(Ruling 345) — 같은 상태 재요청 포함, 다른 사람이 이미 처리했을
      // 수 있어 낡은 화면이 그대로 남지 않도록 명단을 다시 불러온다.
      if (failure case ApiFailure(code: 'RIDER_TRANSITION_NOT_ALLOWED')) {
        ref.invalidate(rosterProvider);
      }
    } finally {
      if (mounted) setState(() => _pendingRiderIds.remove(riderId));
    }
  }

  /// 되돌리기는 처리 기록은 남기되 학부모 알림이 새로 나가는 일이라 한 번 묻는다(시안 `undo`). 닫으면 요청이 없다.
  Future<void> _confirmRevert({
    required String runId,
    required RosterStudent student,
  }) async {
    final confirmed = await showRevertConfirmSheet(context, student: student);
    if (!confirmed || !mounted) return;
    await _revertStatus(runId: runId, riderId: student.riderId);
  }

  Future<void> _revertStatus({
    required String runId,
    required String riderId,
  }) async {
    // 요청 중에 화면이 닫혀도 명단은 갱신해야 한다 — 닫힌 화면의 `ref` 는 쓸 수 없어 컨테이너를 쥔다(F06-16).
    final container = ProviderScope.containerOf(context);
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .revertRiderStatus(runId: runId, riderId: riderId);
      container.invalidate(rosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderIds.remove(riderId));
    }
  }

  /// 명단의 보호자 번호는 마스킹이라 걸 수 없다 — [전화] 를 누른 순간 그 학생 1명의 원번호를
  /// 서버에서 받아 `tel:` 로 연다(Ruling 482). 원번호는 화면에 싣지 않고 바로 전화 앱에 넘긴다.
  /// 번호를 못 받으면 걸지 않고 이유를 알린다.

  /// [미승차 연락] 화면으로 — 학생 하나의 연락 대기 · 기록을 본다.
  void _openNoShow(String riderId) =>
      unawaited(context.push('${AppRoutes.noShow}?rider=$riderId'));

  Future<void> _callGuardianOf({
    required String runId,
    required String riderId,
  }) async {
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    final error = await callGuardian(ref, runId: runId, riderId: riderId);
    if (!mounted) return;
    setState(() {
      _pendingRiderIds.remove(riderId);
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final run = ref.watch(selectedManagerRunProvider);
    final roster = ref.watch(rosterProvider).value;
    final offlineSince = runId == null
        ? null
        : ref.watch(managerOfflineSinceProvider(runId));
    return Scaffold(
      appBar: ManagerHeader(
        title: '명단',
        subtitle: _subtitleOf(roster, run),
        // 탭으로 열린 명단은 뒤로 갈 곳이 없다 — 기사의 조회 전용만 뒤로 가기가 있다.
        onBack: widget.readOnly ? () => Navigator.of(context).maybePop() : null,
        // 연결이 끊겨 있으면 맨 위에 언제부터인지 띠로 알린다(시안 `roster-escort--offline`).
        strip: offlineSince == null
            ? null
            : BaraedaConnectionStrip(
                state: BaraedaConnectionState.offline,
                message: '인터넷 연결 없음 · ${hhmm(offlineSince)} 부터',
              ),
      ),
      body: runId == null
          ? const EmptyState(
              icon: 'list',
              title: '선택된 회차가 없어요',
              body: '회차 탭에서 오늘 운행을 골라 주세요.',
            )
          : _buildBody(context, runId),
    );
  }

  String? _subtitleOf(RosterResponse? roster, ManagerRun? run) {
    final bus = roster?.busNo ?? run?.busNo;
    final direction = roster?.direction ?? run?.direction;
    if (bus == null || direction == null) return null;
    final tail = widget.readOnly
        ? '조회 전용'
        : run == null
        ? null
        : run.runStatus == RunStatus.moving
        ? '운행 중'
        : '${hhmm(run.departTime)} 출발';
    return [bus, directionLabel(direction), ?tail].join(' · ');
  }

  Widget _buildBody(BuildContext context, String runId) {
    final rosterAsync = ref.watch(rosterProvider);
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canDecide =
        !widget.readOnly && (capabilities?.canDecideBoardingStatus ?? false);
    final run = ref.watch(selectedManagerRunProvider);

    // ManagerChannelBanner 는 rosterAsync.when(...) 의 모든 분기 바깥에 둔다 — "명단
    // 없음"(정상, data 분기)과
    // "연결 끊김"(비정상)이 화면에서 구별돼야 한다(목표 9, ManagerChannelBanner 문서 참고).
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          // 재연결 중은 맨 위 연결 끊김 띠가 알린다 — 같은 사건을 두 번 알리지 않는다.
          child: ManagerChannelBanner(runId: runId, hideReconnecting: true),
        ),
        Expanded(
          // 갱신이 실패해도 마지막으로 받은 명단을 지우지 않는다 — 오류는 목록 위에 따로 알린다(R46).
          child: rosterAsync.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const _RosterSkeleton(),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 40),
                EmptyState(
                  icon: 'wifi-off',
                  title: '명단을 불러오지 못했어요',
                  body: '${describeError(error)}\n연결되면 자동으로 다시 불러와요.',
                  action: BaraedaButton(
                    label: '다시 시도',
                    icon: 'refresh',
                    onPressed: () => ref.invalidate(rosterProvider),
                  ),
                ),
              ],
            ),
            data: (roster) => _buildRoster(runId, canDecide, run, roster),
          ),
        ),
      ],
    );
  }

  /// 이 학생에게 지금 처리할 일이 있는가 — 등원은 아직 안 탄 학생, 하원은 아직 안 내린 학생. 위로 올린다.
  bool _needsAction(RosterStudent s, RunDirection direction) =>
      direction == RunDirection.toAcademy
      ? s.status == RiderStatus.waiting || s.status == RiderStatus.noShow
      : s.status == RiderStatus.boarded || s.status == RiderStatus.waiting;

  Widget _buildRoster(
    String runId,
    bool canDecide,
    ManagerRun? run,
    RosterResponse roster,
  ) {
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
    final failedCount = allQueued.length - queuedRequests.length;
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
    final noShowStudents = [
      for (final stop in stops)
        for (final student in stop.students)
          if (student.status == RiderStatus.noShow &&
              student.noShowCase != null)
            student,
    ];

    Widget stopCard(int index) {
      final stop = stops[index];
      final phase = stop.arrivedAt != null
          ? RosterStopPhase.arrived
          : index == currentIndex
          ? RosterStopPhase.current
          : RosterStopPhase.upcoming;
      final students = [...stop.students]
        ..sort(
          (a, b) =>
              (_needsAction(a, roster.direction) ? 0 : 1) -
              (_needsAction(b, roster.direction) ? 0 : 1),
        );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RosterStopCard(
          stop: stop,
          order: index + 1,
          phase: phase,
          expanded:
              phase == RosterStopPhase.current ||
              _expandedStopIds.contains(stop.stopId),
          onToggle: () => setState(() {
            if (!_expandedStopIds.remove(stop.stopId)) {
              _expandedStopIds.add(stop.stopId);
            }
          }),
          waitingCount: stop.students
              .where((s) => _needsAction(s, roster.direction))
              .length,
          noShowCount: stop.students
              .where((s) => s.status == RiderStatus.noShow)
              .length,
          children: [
            for (final student in students)
              _studentTile(
                runId,
                roster,
                student,
                canDecide: canDecide,
                photoHeaders: photoHeaders,
                queued: queuedRiderIds.contains(student.riderId),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(rosterProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (refreshError != null) ...[
            AlertBanner(
              tone: AlertTone.missed,
              title: '최신 명단을 불러오지 못했어요',
              body: '이전 명단을 보고 있어요 · ${describeError(refreshError)}',
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
          if (widget.readOnly)
            const AlertBanner(
              tone: AlertTone.info,
              icon: 'eye',
              body: '기사는 명단을 볼 수만 있어요. 승차 · 하차 처리는 동승자가 해요.',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // UF-E-05 "명단 → [지연 알림]" — M-05 는 **동승자 전용**(기사는 운전 중).
                if (caps?.canSendDelayNotification ?? false)
                  BaraedaButton(
                    label: '지연 알림',
                    size: BaraedaButtonSize.sm,
                    icon: 'clock',
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: () => unawaited(context.push(AppRoutes.delay)),
                  ),
                // 예외 보고(M-14, R32 M3) — 보호자 부재·도로 통제 등. 기사는 운행 화면의 종료 보고서로,
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
                if (caps?.canDecideBoardingStatus ?? false)
                  BaraedaButton(
                    label: allQueued.isEmpty
                        ? '대기열'
                        : '대기열 ${allQueued.length}건',
                    icon: 'inbox',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: () =>
                        unawaited(context.push(AppRoutes.offlineQueue)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          if (!widget.readOnly && noShowStudents.isNotEmpty) ...[
            _NoShowWaitBanner(
              student: noShowStudents.first,
              onContact: () => _openNoShow(noShowStudents.first.riderId),
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
          if (_errorMessage != null) ...[
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
            const SizedBox(height: 12),
          ],
          if (queuedRequests.isNotEmpty) ...[
            // 큐에 쌓인 처리가 있는 동안은 다음 조작이 이 안내를 지우지 않는다 — 큐가 비면 사라진다(R46).
            AlertBanner(
              tone: AlertTone.moving,
              body: '처리되지 않았어요 · 대기 중 ${queuedRequests.length}건',
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
          if (!widget.readOnly &&
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
            _PastStopsCard(
              stops: [for (final i in arrivedIndexes) stops[i]],
              expanded: _pastExpanded,
              onToggle: () => setState(() => _pastExpanded = !_pastExpanded),
            ),
            const SizedBox(height: 12),
            if (_pastExpanded)
              for (final i in arrivedIndexes) stopCard(i),
          ],
          for (var i = 0; i < stops.length; i++)
            if (stops[i].arrivedAt == null) stopCard(i),
        ],
      ),
    );
  }

  Widget _studentTile(
    String runId,
    RosterResponse roster,
    RosterStudent student, {
    required bool canDecide,
    required Map<String, String>? photoHeaders,
    required bool queued,
  }) {
    final busy = _pendingRiderIds.contains(student.riderId);
    // M1(Ruling 341, BR-016) — `absent`(`change=removed`) 행은 버스 간 이동으로 빠진
    // 학생이라 조작 대상이
    // 아니다. 배지만 보여주고 [탑승]·[미승차] 등은 아예 그리지 않는다(canDecide 여부와 무관).
    final badge = student.status == RiderStatus.absent
        ? const BaraedaBadge(label: '금일 삭제', tone: BaraedaBadgeTone.removed)
        : queued
        ? const BaraedaBadge(label: '전송 대기', tone: BaraedaBadgeTone.amber)
        : null;
    final expiry =
        student.status == RiderStatus.noShow && student.noShowCase != null
        ? '${hhmm(student.noShowCase!.expiresAt)} 까지 연락 대기'
        : null;
    return RosterStudentTile(
      student: student,
      ride: _rideStatusOf(student),
      photoHeaders: photoHeaders,
      metaExtra: expiry,
      badge: badge,
      busy: busy,
      actions: badge != null || !canDecide
          ? null
          : _actions(runId, roster, student, busy: busy),
    );
  }

  Widget? _actions(
    String runId,
    RosterResponse roster,
    RosterStudent student, {
    required bool busy,
  }) {
    final riderId = student.riderId;
    // 연결된 보호자가 없으면(명단 번호가 비어 옴) 걸 곳이 없어 단추를 그리지 않는다. 번호 자체는 마스킹돼 있어
    // 누른 순간 서버에서 원번호를 따로 받는다(Ruling 482).
    final call = student.guardianPhone == null
        ? null
        : RosterCallButton(
            onPressed: busy
                ? null
                : () => unawaited(
                    _callGuardianOf(runId: runId, riderId: riderId),
                  ),
          );
    final revert = Align(
      alignment: Alignment.centerRight,
      child: BaraedaButton(
        label: '되돌리기',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.ghost,
        onPressed: busy
            ? null
            : () => unawaited(_confirmRevert(runId: runId, student: student)),
      ),
    );
    // 처리 단추가 [미승차] 보다 넓다(C1) — 자주 누르는 쪽이 크다.
    Widget row(List<(int, Widget)> items) => Row(
      children: [
        ?call,
        if (call != null) const SizedBox(width: 8),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(flex: item.$1, child: item.$2),
        ],
      ],
    );
    switch (student.status) {
      case RiderStatus.waiting:
        return row([
          (
            17,
            BaraedaButton(
              label: '탑승',
              icon: 'check',
              block: true,
              onPressed: busy
                  ? null
                  : () => unawaited(
                      _updateStatus(
                        runId: runId,
                        riderId: riderId,
                        status: RiderStatus.boarded,
                      ),
                    ),
            ),
          ),
          (
            10,
            BaraedaButton(
              label: '미승차',
              variant: BaraedaButtonVariant.dangerOutline,
              block: true,
              onPressed: busy
                  ? null
                  : () => unawaited(
                      _confirmNoShow(
                        runId: runId,
                        riderId: riderId,
                        name: student.name,
                      ),
                    ),
            ),
          ),
        ]);
      case RiderStatus.boarded:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([
              (
                1,
                BaraedaButton(
                  label: '하차',
                  icon: 'check',
                  block: true,
                  onPressed: busy
                      ? null
                      : () => unawaited(
                          _updateStatus(
                            runId: runId,
                            riderId: riderId,
                            status: RiderStatus.alighted,
                          ),
                        ),
                ),
              ),
            ]),
            revert,
          ],
        );
      case RiderStatus.noShow:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([
              (
                1,
                BaraedaButton(
                  label: '연락 기록',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                  onPressed: busy ? null : () => _openNoShow(riderId),
                ),
              ),
            ]),
            revert,
          ],
        );
      case RiderStatus.alighted:
        return revert;
      case RiderStatus.absent:
        // 위에서 배지로 대체해 도달하지 않지만 exhaustiveness 를 위해 채운다.
        return null;
    }
  }

  RideStatus _rideStatusOf(RosterStudent student) => switch (student.status) {
    RiderStatus.waiting => RideStatus.waiting,
    RiderStatus.boarded => RideStatus.boarded,
    RiderStatus.alighted => RideStatus.alighted,
    RiderStatus.noShow => RideStatus.missed,
    RiderStatus.absent => RideStatus.absent,
  };
}

/// 미승차 연락 대기 띠 — `오시우 미승차 · 연락 대기 1:12` + `연락`. 1초마다 남은 시간을 다시 그린다.
class _NoShowWaitBanner extends ConsumerStatefulWidget {
  const new({required this.student, required this.onContact});

  final RosterStudent student;
  final VoidCallback onContact;

  @override
  ConsumerState<_NoShowWaitBanner> createState() => _NoShowWaitBannerState();
}

class _NoShowWaitBannerState extends ConsumerState<_NoShowWaitBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final case_ = widget.student.noShowCase!;
    final left = case_.expiresAt.difference(ref.watch(clockProvider).now());
    final remaining = left.isNegative ? Duration.zero : left;
    final text = remaining == Duration.zero
        ? '${widget.student.name} 미승차 · 연락 대기가 끝났어요'
        : '${widget.student.name} 미승차 · 연락 대기 '
              '${remaining.inMinutes}:'
              '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return AlertBanner(
      tone: AlertTone.moving,
      icon: 'clock',
      title: text,
      inlineAction: true,
      action: BaraedaButton(
        label: '연락',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: widget.onContact,
      ),
    );
  }
}

/// `지난 승하차지 2곳 / 푸른아파트 앞 · 중앙공원 앞 [미승차 1] ›` — 지나온 곳을 한 줄로 접어 둔다.
class _PastStopsCard extends StatelessWidget {
  const new({
    required this.stops,
    required this.expanded,
    required this.onToggle,
  });

  final List<RosterStop> stops;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final noShow = stops
        .expand((s) => s.students)
        .where((s) => s.status == RiderStatus.noShow)
        .length;
    return BaraedaCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentPrimary,
                ),
                child: BaraedaIcon(
                  'check',
                  size: 18,
                  color: colors.textInverse,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '지난 승하차지 ${stops.length}곳',
                      style: BaraedaTypography.body.copyWith(
                        fontWeight: BaraedaFontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      stops.map((s) => s.name).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (noShow > 0) ...[
                const SizedBox(width: 8),
                BaraedaStatusPill(
                  status: BaraedaStatus.missed,
                  label: '미승차 $noShow',
                ),
              ],
              const SizedBox(width: 4),
              BaraedaIcon(
                expanded ? 'chevron-down' : 'chevron-right',
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: const [
      BaraedaSkeleton(height: 72, radius: 16),
      SizedBox(height: 12),
      BaraedaSkeletonList(count: 4),
    ],
  );
}
