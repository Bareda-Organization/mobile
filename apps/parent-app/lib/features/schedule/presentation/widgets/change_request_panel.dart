import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';
import 'package:parent_app/features/schedule/presentation/widgets/sticky_action_bar.dart';

/// 회차 선택 목록에 쓰는 표시 문구 — `방향 · 버스번호번`. 위젯 시험이
/// 이 문구를 직접 적어 두면 라벨 문구(`RunDirection.label`)가 바뀔 때
/// 무관한 사유로 조용히 깨진다 — 여기 노출해 시험이 값으로 참조하게 한다.
// `bus_no` 는 호차 **이름 그 자체**다(`ERD bus.bus_no varchar(20)` · 시드 '1호차').
// 단위를 덧붙이면 "1호차번" 이 된다.
String runOptionLabel(StudentRun run) =>
    '${run.direction.label} · ${run.busNo}';

/// §3.8 — 일일 변경 신청. 날짜(오늘·내일, 한국 시간)를 고르면 `core/runs` 의
/// §3.5 조회가 그날 회차를 주고, 그중 하나를 대상으로 신청한다(R48 시안 `daily-change`).
///
/// 신청 이력(§3.9)은 일정 탭 맨 아래로 옮겼다. 제출하면 신청 내용 영수증이 이 화면을
/// 대신한다(`daily-change--done`).
class ChangeRequestPanel extends ConsumerStatefulWidget {
  const new({required this.studentId, super.key});

  final String studentId;

  @override
  ConsumerState<ChangeRequestPanel> createState() => _ChangeRequestPanelState();
}

class _ChangeRequestPanelState extends ConsumerState<ChangeRequestPanel> {
  final _addressController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _selectedRunId;

  /// 0 = 오늘, 1 = 내일 (한국 시간).
  int _dayOffset = 0;
  ChangeRequestType _type = ChangeRequestType.cancel;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// 제출에 성공했을 때 접수 내용 — 있으면 폼 대신 영수증을 그린다.
  _Receipt? _receipt;

  /// dispose 에서는 `ref` 를 못 쓰므로 미리 잡아 둔다.
  late final UnsavedEdits _edits;

  @override
  void initState() {
    super.initState();
    _edits = ref.read(scheduleUnsavedEditsProvider);
    // 주소를 적는 동안 [제출할 수 없는 이유] 안내가 바로 사라지도록 글자 변화를 화면에 알린다.
    _addressController.addListener(_onInputChanged);
    _reasonController.addListener(_reportDirty);
  }

  void _onInputChanged() {
    setState(() {});
    _reportDirty();
  }

  /// 적어 둔 주소·사유가 있는지 일정 화면에 알린다(뒤로가기 확인용, R32 P14).
  void _reportDirty() {
    final dirty =
        _reasonController.text.trim().isNotEmpty ||
        (_type == ChangeRequestType.relocate &&
            _addressController.text.trim().isNotEmpty);
    _edits.mark(this, dirty: dirty);
  }

  /// 지금 제출할 수 없다면 그 이유 — 제출 가능하면 null (R32 P12).
  String? get _missingInput {
    if (_selectedRunId == null) return '대상 회차를 골라 주세요';
    if (_type == ChangeRequestType.relocate &&
        _addressController.text.trim().isEmpty) {
      return '변경할 주소를 입력해 주세요';
    }
    return null;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _reasonController.dispose();
    super.dispose();
    // 화면이 그려지는 도중에 구독자(일정 화면)를 흔들지 않도록 한 박자 뒤에 지운다.
    scheduleMicrotask(() => _edits.mark(this, dirty: false));
  }

  Future<void> _submit() async {
    final runId = _selectedRunId;
    if (runId == null || _submitting) return;
    if (_type == ChangeRequestType.relocate &&
        _addressController.text.trim().isEmpty) {
      setState(() {
        _bannerTone = AlertTone.missed;
        _banner = '변경할 주소를 입력해 주세요';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _banner = null;
    });

    try {
      final result = await ref
          .read(changeRequestRepositoryProvider)
          .createChangeRequest(
            widget.studentId,
            type: _type,
            runId: runId,
            newAddress: _type == ChangeRequestType.relocate
                ? _addressController.text.trim()
                : null,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
      if (!mounted) return;
      final run = _runsOfDay.where((r) => r.runId == runId).firstOrNull;
      final address = _addressController.text.trim();
      final reason = _reasonController.text.trim();
      setState(() {
        _submitting = false;
        _receipt = _Receipt(
          pendingApproval: result.result == 'pending_approval',
          deadlineAt: result.deadlineAt,
          run: run == null
              ? null
              : '${run.direction.label} · ${formatClock(run.departTime)} 출발',
          originalStop: run?.stop.name,
          type: _type,
          address: _type == ChangeRequestType.relocate ? address : null,
          reason: reason.isEmpty ? null : reason,
        );
      });
      // 접수한 내용은 더 이상 저장 안 된 입력이 아니다 — 비워서 같은 내용의 재접수도 막는다.
      _addressController.clear();
      _reasonController.clear();
      _reportDirty();
      ref
        ..invalidate(changeRequestsProvider(widget.studentId))
        // F05-03 — ① 구간 신청은 즉시 반영되므로 홈 카드(탑승 스위치·승하차지)도 다시 받는다.
        ..invalidate(runsForStudentProvider(widget.studentId))
        ..invalidate(runsForStudentOnProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(code: 'CHANGE_WINDOW_CLOSED') => '운행 중에는 신청할 수 없습니다',
          ApiFailure(code: 'CHANGE_LIMIT_REACHED') =>
            '이 회차는 변경 가능 횟수를 모두 사용했습니다',
          ApiFailure(code: 'ADDRESS_VERIFICATION_FAILED') =>
            '주소를 확인할 수 없습니다. 다시 입력해 주세요',
          ApiFailure(code: 'RUN_CANCELED') => runCanceledMessage,
          _ => failureMessage(failure, fallback: '신청을 처리하지 못했습니다'),
        };
      });
    }
  }

  /// 오늘은 서버 기본값(당일) 조회를 그대로 쓰고, 내일은 한국 시간 날짜를 `date` 로 보낸다.
  AsyncValue<List<StudentRun>> _watchRuns() => _dayOffset == 0
      ? ref.watch(runsForStudentProvider(widget.studentId))
      : ref.watch(
          runsForStudentOnProvider((
            widget.studentId,
            koreaServiceDate(
              ref.watch(clockProvider).now(),
              plusDays: _dayOffset,
            ),
          )),
        );

  List<StudentRun> get _runsOfDay =>
      (_dayOffset == 0
              ? ref.read(runsForStudentProvider(widget.studentId))
              : ref.read(
                  runsForStudentOnProvider((
                    widget.studentId,
                    koreaServiceDate(
                      ref.read(clockProvider).now(),
                      plusDays: _dayOffset,
                    ),
                  )),
                ))
          .value ??
      const [];

  @override
  Widget build(BuildContext context) {
    // 영수증 화면에서도 회차 조회를 계속 본다 — 신청이 반영된 뒤 홈 카드가 새 값을 받게 무효화한 것을 이 구독이 받는다.
    final runsAsync = _watchRuns();
    final receipt = _receipt;
    if (receipt != null) return _buildReceipt(receipt);

    final runs = runsAsync.value;
    final selectedRun = runs
        ?.where((r) => r.runId == _selectedRunId)
        .firstOrNull;
    final canSubmit = !_submitting && _missingInput == null;
    // 구간②(승인 필요)는 단추 글자부터 다르다 — 취소가 즉시 되는 줄 아는 오해를 막는다(P2).
    final needsApproval =
        selectedRun != null && _zoneOf(selectedRun) == _Zone.approval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
            children: [
              _buildDayPicker(),
              const SizedBox(height: BaraedaSpacing.space4),
              const _FieldTitle('어느 회차예요?'),
              runsAsync.when(
                skipError: true,
                loading: () => const BaraedaSkeletonList(count: 2),
                error: (error, stack) => const AlertBanner(
                  tone: AlertTone.missed,
                  body: '회차를 불러오지 못했어요',
                ),
                data: (runs) => runs.isEmpty
                    ? const WordWrapText('그날 운행이 아직 없어요')
                    : _buildRunChoices(runs),
              ),
              if (selectedRun != null) ...[
                const SizedBox(height: BaraedaSpacing.space3),
                _buildZoneNotice(selectedRun),
                const SizedBox(height: BaraedaSpacing.space4),
                const _FieldTitle('어떻게 바꿀까요?'),
                _buildTypePicker(),
                if (_type == ChangeRequestType.relocate) ...[
                  const SizedBox(height: BaraedaSpacing.space3),
                  BaraedaInput(label: '변경할 주소', controller: _addressController),
                  const SizedBox(height: BaraedaSpacing.space1),
                  Text(
                    '주소를 확인한 뒤 노선에 반영해요',
                    style: BaraedaTypography.bodySm.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: BaraedaSpacing.space3),
                BaraedaTextarea(
                  label: '사유 (선택)',
                  controller: _reasonController,
                ),
              ],
              if (_banner != null) ...[
                const SizedBox(height: BaraedaSpacing.space3),
                AlertBanner(tone: _bannerTone, body: _banner),
              ],
            ],
          ),
        ),
        StickyActionBar(
          child: BaraedaButton(
            label: needsApproval ? '승인 요청 보내기' : '변경 신청하기',
            block: true,
            // 단추가 왜 꺼졌는지 단추 아래 글로 알려 준다(R32 P12).
            disabledReason: canSubmit ? null : _missingInput,
            onPressed: canSubmit ? _submit : null,
          ),
        ),
      ],
    );
  }

  /// 신청할 날짜 — 오늘·내일 두 가지. 날짜를 바꾸면 앞서 고른 회차는 다른 날 것이라 비운다.
  Widget _buildDayPicker() {
    return BaraedaSegmentedControl(
      block: true,
      options: const [
        BaraedaSegmentedOption('0', label: '오늘'),
        BaraedaSegmentedOption('1', label: '내일'),
      ],
      value: '$_dayOffset',
      onChanged: (value) => setState(() {
        _dayOffset = int.parse(value);
        _selectedRunId = null;
      }),
    );
  }

  /// 회차 라디오 칸 — 운행이 시작됐거나 끝난 회차는 이유와 함께 꺼진다(탑승 취소는 홈에서).
  Widget _buildRunChoices(List<StudentRun> runs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs) ...[
          if (run != runs.first) const SizedBox(height: BaraedaSpacing.space2),
          BaraedaChoiceTile(
            title: '${run.direction.label} · ${formatClock(run.departTime)} 출발',
            subtitle: '${run.stop.name} · ${run.busNo}',
            selected: run.runId == _selectedRunId,
            disabledReason: switch (run.runStatus) {
              RunStatus.moving => '운행이 시작되어 바꿀 수 없어요 · 탑승 취소는 홈에서',
              RunStatus.finished => '운행이 끝났어요',
              RunStatus.idle || RunStatus.confirmed => null,
            },
            trailing: _runChip(run),
            onTap: () => setState(() => _selectedRunId = run.runId),
          ),
        ],
      ],
    );
  }

  Widget _runChip(StudentRun run) => switch (run.runStatus) {
    RunStatus.moving => const BaraedaStatusPill(
      status: BaraedaStatus.moving,
      label: '이동 중',
    ),
    RunStatus.finished => const BaraedaStatusPill(
      status: BaraedaStatus.idle,
      label: '종료',
    ),
    RunStatus.confirmed => const BaraedaStatusPill(
      status: BaraedaStatus.boarded,
      label: '확정',
    ),
    RunStatus.idle => BaraedaStatusPill(
      status: run.confirmed ? BaraedaStatus.boarded : BaraedaStatus.waiting,
      label: run.confirmed ? '확정' : '확정 전',
    ),
  };

  /// 구간 안내 띠 — ①바로 반영 / ②승인이 필요해요(회차당 1번).
  Widget _buildZoneNotice(StudentRun run) {
    final confirmAt = formatClock(
      run.departTime.subtract(const Duration(minutes: 30)),
    );
    final departAt = formatClock(run.departTime);
    return switch (_zoneOf(run)) {
      _Zone.immediate => AlertBanner(
        tone: AlertTone.info,
        title: '바로 반영돼요',
        body: '$confirmAt 이후에는 학원 승인이 필요해요',
      ),
      _Zone.approval => AlertBanner(
        tone: AlertTone.moving,
        title: '학원 승인이 필요해요',
        body: '이 회차에서 1번만 신청할 수 있어요. $departAt 까지 승인되지 않으면 자동 반려돼요.',
      ),
    };
  }

  Widget _buildTypePicker() {
    return BaraedaSegmentedControl(
      block: true,
      options: const [
        BaraedaSegmentedOption('cancel', label: '탑승 취소'),
        BaraedaSegmentedOption('relocate', label: '승하차지 변경'),
      ],
      value: _type.wireValue,
      onChanged: (value) {
        setState(() => _type = ChangeRequestType.fromWireValue(value));
        _reportDirty();
      },
    );
  }

  /// 제출 뒤 화면 — 무엇을 신청했는지 영수증으로 보여 주고, 승인 전에는 원래 승하차지로 버스가 온다는 말을 한다(P1).
  Widget _buildReceipt(_Receipt receipt) {
    final deadline = receipt.deadlineAt;
    final deadlineText = deadline == null
        ? '학원이 확인하면 알림으로 알려 드려요'
        : '마감 ${formatDateTime(deadline)} · 학원이 확인하면 알림으로 알려 드려요';
    return ListView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      children: [
        AlertBanner(
          tone: receipt.pendingApproval ? AlertTone.moving : AlertTone.boarded,
          title: receipt.pendingApproval ? '승인 요청을 보냈어요' : '변경했어요',
          body: receipt.pendingApproval ? deadlineText : '바로 반영됐어요',
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaReceiptCard(
          title: '신청 내용',
          rows: [
            if (receipt.run != null) BaraedaReceiptRow('회차', receipt.run!),
            BaraedaReceiptRow(
              '변경',
              receipt.type == ChangeRequestType.cancel ? '탑승 취소' : '승하차지 변경',
            ),
            if (receipt.address != null)
              BaraedaReceiptRow('변경할 주소', receipt.address!),
            if (receipt.reason != null)
              BaraedaReceiptRow('사유', receipt.reason!),
          ],
        ),
        if (receipt.pendingApproval) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          Text(
            [
              if (receipt.originalStop != null)
                '승인되기 전까지는 원래 승하차지(${receipt.originalStop})로 버스가 와요.',
              if (deadline != null)
                '${formatClock(deadline)} 까지 승인되지 않으면 자동으로 반려돼요.',
            ].join(' '),
            style: BaraedaTypography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: BaraedaSpacing.space6),
        BaraedaButton(
          label: '일정으로 돌아가기',
          block: true,
          onPressed: () => context.go(AppRoutes.schedule),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaButton(
          label: '신청 이력 보기',
          block: true,
          variant: BaraedaButtonVariant.ghost,
          onPressed: () => context.go(AppRoutes.schedule),
        ),
      ],
    );
  }
}

/// 신청 구간 — 서버가 준 `run_status`·`confirmed` 로만 가른다(시각으로 계산하지 않는다).
/// 일일 변경에서 고를 수 있는 회차는 운행 전(`idle`·`confirmed`)뿐이다.
enum _Zone { immediate, approval }

_Zone _zoneOf(StudentRun run) =>
    run.runStatus == RunStatus.idle && !run.confirmed
    ? _Zone.immediate
    : _Zone.approval;

/// 제출 성공 때 영수증에 쓸 값 — 폼이 비워지기 전에 담아 둔다.
class _Receipt {
  const new({
    required this.pendingApproval,
    required this.type,
    this.deadlineAt,
    this.run,
    this.originalStop,
    this.address,
    this.reason,
  });

  final bool pendingApproval;
  final DateTime? deadlineAt;
  final String? run;
  final String? originalStop;
  final ChangeRequestType type;
  final String? address;
  final String? reason;
}

class _FieldTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Text(
        text,
        style: BaraedaTypography.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: BaraedaFontWeight.bold,
        ),
      ),
    );
  }
}
