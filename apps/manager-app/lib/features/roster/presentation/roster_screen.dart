import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// StopRoster — 정류장별 탑승자 명단 (§4.2 M-03 · §4.6 M-12 · §4.7 M-13 ·
/// §4.8 M-14).
///
/// 기사·동승자 둘 다 조회하지만(API_SPEC "버스기사(조회)"), 승하차 상태를
/// 바꾸는 버튼은 `canDecideBoardingStatus`(동승자 전용, role_policy.dart)
/// 로만 노출된다 — 같은 화면에서 버튼 노출이 갈리는 또 다른 예시(§1.1).
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  String? _pendingRiderId;
  String? _errorMessage;

  Future<void> _updateStatus({
    required String runId,
    required String riderId,
    required RiderStatus status,
  }) async {
    setState(() {
      _pendingRiderId = riderId;
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .updateRiderStatus(
            runId: runId,
            riderId: riderId,
            request: BoardingUpdateRequest(
              status: status,
              clientKey: IdempotencyKeys.generate(),
            ),
          );
      ref.invalidate(rosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  Future<void> _revertStatus({
    required String runId,
    required String riderId,
  }) async {
    setState(() {
      _pendingRiderId = riderId;
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .revertRiderStatus(runId: runId, riderId: riderId);
      ref.invalidate(rosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  Future<void> _recordNoShowContact({
    required String runId,
    required String riderId,
  }) async {
    final request = await showModalBottomSheet<NoShowContactRequest>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _NoShowContactSheet(),
    );
    if (request == null || !mounted) return;
    setState(() {
      _pendingRiderId = riderId;
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .recordNoShowContact(
            runId: runId,
            riderId: riderId,
            request: request,
          );
      ref.invalidate(rosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('승하차 명단')),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId),
    );
  }

  Widget _buildBody(BuildContext context, String runId) {
    final rosterAsync = ref.watch(rosterProvider);
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canDecide = capabilities?.canDecideBoardingStatus ?? false;

    return rosterAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('명단을 불러오지 못했습니다: $error')),
      data: (roster) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: '탑승',
                  value: '${roster.counts.boarded}',
                  tone: StatCardTone.boarded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(label: '대기', value: '${roster.counts.waiting}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  label: '미탑승',
                  value: '${roster.counts.noShow}',
                  tone: StatCardTone.missed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(label: '결석', value: '${roster.counts.absentN}'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
            const SizedBox(height: 12),
          ],
          for (final stop in roster.stops)
            _StopSection(
              stop: stop,
              canDecide: canDecide,
              pendingRiderId: _pendingRiderId,
              onBoard: (riderId) => _updateStatus(
                runId: runId,
                riderId: riderId,
                status: RiderStatus.boarded,
              ),
              onAlight: (riderId) => _updateStatus(
                runId: runId,
                riderId: riderId,
                status: RiderStatus.alighted,
              ),
              onNoShow: (riderId) => _updateStatus(
                runId: runId,
                riderId: riderId,
                status: RiderStatus.noShow,
              ),
              onRevert: (riderId) =>
                  _revertStatus(runId: runId, riderId: riderId),
              onRecordContact: (riderId) =>
                  _recordNoShowContact(runId: runId, riderId: riderId),
            ),
        ],
      ),
    );
  }
}

/// 정류장 한 곳 — 헤더(순번·이름·도착 시각) + 탑승자 행 목록.
///
/// `StopTimeline` 은 정류장 순서 요약(웹·다른 화면)에 쓰는 컴포넌트라 인원
/// 집계까지만 보여준다 — 개인별 행·액션 버튼이 필요한 이 화면에는 맞지
/// 않아 직접 헤더+`StudentRow` 목록을 조합했다(설계 판단, 보고서 참고).
class _StopSection extends StatelessWidget {
  const _StopSection({
    required this.stop,
    required this.canDecide,
    required this.pendingRiderId,
    required this.onBoard,
    required this.onAlight,
    required this.onNoShow,
    required this.onRevert,
    required this.onRecordContact,
  });

  final RosterStop stop;
  final bool canDecide;
  final String? pendingRiderId;
  final void Function(String riderId) onBoard;
  final void Function(String riderId) onAlight;
  final void Function(String riderId) onNoShow;
  final void Function(String riderId) onRevert;
  final void Function(String riderId) onRecordContact;

  @override
  Widget build(BuildContext context) {
    final skipped = stop.change == StopChange.skipped;
    final arrivedAt = stop.arrivedAt;
    final headerTrailing = skipped
        ? (stop.skipNotice ?? '경유하지 않음')
        : (arrivedAt == null
              ? '미도착'
              : '${DateFormat('HH:mm').format(arrivedAt)} 도착');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${stop.seq}. ${stop.name}',
                style:
                    Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
              ),
              const Spacer(),
              Text(
                headerTrailing,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          for (final student in stop.students)
            StudentRow(
              name: student.name,
              meta: [
                student.className,
                student.guardianPhone,
              ].whereType<String>().join(' · '),
              ride: _rideStatusOf(student),
              actions: canDecide
                  ? _StudentActions(
                      student: student,
                      busy: pendingRiderId == student.riderId,
                      onBoard: () => onBoard(student.riderId),
                      onAlight: () => onAlight(student.riderId),
                      onNoShow: () => onNoShow(student.riderId),
                      onRevert: () => onRevert(student.riderId),
                      onRecordContact: () => onRecordContact(student.riderId),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  RideStatus _rideStatusOf(RosterStudent student) => switch (student.status) {
    RiderStatus.waiting => RideStatus.waiting,
    RiderStatus.boarded => RideStatus.boarded,
    RiderStatus.alighted => RideStatus.alighted,
    RiderStatus.noShow => RideStatus.missed,
  };
}

/// 탑승자 한 명의 상태 전환 버튼 — 현재 [RiderStatus] 에 따라 다음 동작만
/// 보여준다. `busy` 인 동안(요청 진행 중) 전부 비활성화한다.
class _StudentActions extends StatelessWidget {
  const _StudentActions({
    required this.student,
    required this.busy,
    required this.onBoard,
    required this.onAlight,
    required this.onNoShow,
    required this.onRevert,
    required this.onRecordContact,
  });

  final RosterStudent student;
  final bool busy;
  final VoidCallback onBoard;
  final VoidCallback onAlight;
  final VoidCallback onNoShow;
  final VoidCallback onRevert;
  final VoidCallback onRecordContact;

  @override
  Widget build(BuildContext context) {
    // BaraedaIcon 매핑 표(패키지 소유, 이번 라운드에서 건드리지 않음)에
    // "되돌리기"에 맞는 이름이 없어 아이콘 대신 텍스트 버튼을 쓴다.
    final revertButton = BaraedaButton(
      label: '되돌리기',
      size: BaraedaButtonSize.sm,
      variant: BaraedaButtonVariant.ghost,
      onPressed: busy ? null : onRevert,
    );

    switch (student.status) {
      case RiderStatus.waiting:
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BaraedaButton(
              label: '탑승',
              size: BaraedaButtonSize.sm,
              onPressed: busy ? null : onBoard,
            ),
            BaraedaButton(
              label: '미탑승',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.danger,
              onPressed: busy ? null : onNoShow,
            ),
          ],
        );
      case RiderStatus.boarded:
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BaraedaButton(
              label: '하차',
              size: BaraedaButtonSize.sm,
              onPressed: busy ? null : onAlight,
            ),
            revertButton,
          ],
        );
      case RiderStatus.noShow:
        final expiresAt = student.noShowCase?.expiresAt;
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (expiresAt != null)
              Text(
                '${DateFormat('HH:mm:ss').format(expiresAt)} 만료',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            BaraedaButton(
              label: '연락 기록',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: busy ? null : onRecordContact,
            ),
            revertButton,
          ],
        );
      case RiderStatus.alighted:
        return revertButton;
    }
  }
}

/// §4.8 연락 시도 기록 입력 — 연락 수단·결과·(선택)최종 판단.
class _NoShowContactSheet extends StatefulWidget {
  const _NoShowContactSheet();

  @override
  State<_NoShowContactSheet> createState() => _NoShowContactSheetState();
}

class _NoShowContactSheetState extends State<_NoShowContactSheet> {
  NoShowAttemptType _attemptType = NoShowAttemptType.call;
  NoShowContactResult _result = NoShowContactResult.noAnswer;
  NoShowDecision? _decision;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('미탑승 연락 기록', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const Text('연락 수단'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in NoShowAttemptType.values)
                  ChoiceChip(
                    label: Text(type == NoShowAttemptType.call ? '전화' : '문자'),
                    selected: _attemptType == type,
                    onSelected: (_) => setState(() => _attemptType = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('결과'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final result in NoShowContactResult.values)
                  ChoiceChip(
                    label: Text(
                      result == NoShowContactResult.answered ? '응답함' : '무응답',
                    ),
                    selected: _result == result,
                    onSelected: (_) => setState(() => _result = result),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('최종 판단 (3분 경과 후에만 선택)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('미정'),
                  selected: _decision == null,
                  onSelected: (_) => setState(() => _decision = null),
                ),
                for (final decision in NoShowDecision.values)
                  ChoiceChip(
                    label: Text(
                      decision == NoShowDecision.depart ? '출발 확정' : '재시도',
                    ),
                    selected: _decision == decision,
                    onSelected: (_) => setState(() => _decision = decision),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            BaraedaButton(
              label: '기록 저장',
              block: true,
              onPressed: () => Navigator.of(context).pop(
                NoShowContactRequest(
                  attemptType: _attemptType,
                  result: _result,
                  decision: _decision,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
