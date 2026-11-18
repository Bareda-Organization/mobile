import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_form.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_receipt.dart';

/// 회차 선택 목록에 쓰는 표시 문구 — `방향 · 버스번호번`. 위젯 시험이
/// 이 문구를 직접 적어 두면 라벨 문구(`RunDirection.label`)가 바뀔 때
/// 무관한 사유로 조용히 깨진다 — 여기 노출해 시험이 값으로 참조하게 한다.
// `bus_no` 는 호차 **이름 그 자체**다(`ERD bus.bus_no varchar(20)` · 시드 '1호차').
// 단위를 덧붙이면 "1호차번" 이 된다.
String runOptionLabel(StudentRun run) =>
    '${run.direction.label} · ${run.busNo}';

/// §3.8 — 일일 변경 신청. 날짜(오늘·내일, 한국 시간)를 고르면 `core/runs` 의
/// §3.5 조회가 그날 회차를 주고, 그중 하나를 대상으로 신청한다.
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
  ChangeRequestReceiptData? _receipt;

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

  /// 적어 둔 주소·사유가 있는지 일정 화면에 알린다(뒤로가기 확인용).
  void _reportDirty() {
    final dirty =
        _reasonController.text.trim().isNotEmpty ||
        (_type == ChangeRequestType.relocate &&
            _addressController.text.trim().isNotEmpty);
    _edits.mark(this, dirty: dirty);
  }

  /// 지금 제출할 수 없다면 그 이유 — 제출 가능하면 null.
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
      final run = _readRuns(
        ref,
        widget.studentId,
        _dayOffset,
      ).where((r) => r.runId == runId).firstOrNull;
      setState(() {
        _submitting = false;
        _receipt = ChangeRequestReceiptData.submitted(
          pendingApproval: result.result == 'pending_approval',
          deadlineAt: result.deadlineAt,
          run: run,
          type: _type,
          address: _addressController.text.trim(),
          reason: _reasonController.text.trim(),
        );
      });
      // 접수한 내용은 더 이상 저장 안 된 입력이 아니다 — 비워서 같은 내용의 재접수도 막는다.
      _addressController.clear();
      _reasonController.clear();
      _reportDirty();
      ref
        ..invalidate(changeRequestsProvider(widget.studentId))
        // ① 구간 신청은 즉시 반영되므로 홈 카드(탑승 스위치·승하차지)도 다시 받는다.
        ..invalidate(runsForStudentProvider(widget.studentId))
        ..invalidate(runsForStudentOnProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = _submitFailureMessage(failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 영수증 화면에서도 회차 조회를 계속 본다 — 신청이 반영된 뒤 홈 카드가 새 값을 받게 무효화한 것을 이 구독이 받는다.
    final runsAsync = _watchRuns(ref, widget.studentId, _dayOffset);
    final receipt = _receipt;
    if (receipt != null) return ChangeRequestReceipt(receipt: receipt);

    final selectedRun = runsAsync.value
        ?.where((r) => r.runId == _selectedRunId)
        .firstOrNull;
    final canSubmit = !_submitting && _missingInput == null;
    // 구간②(승인 필요)는 단추 글자부터 다르다 — 취소가 즉시 되는 줄 아는 오해를 막는다.
    final needsApproval =
        selectedRun != null &&
        changeZoneOf(selectedRun, ref.read(clockProvider).now()) ==
            ChangeZone.approval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ChangeRequestForm(
            dayOffset: _dayOffset,
            // 날짜를 바꾸면 앞서 고른 회차는 다른 날 것이라 비운다.
            onDayChanged: (offset) => setState(() {
              _dayOffset = offset;
              _selectedRunId = null;
            }),
            runsAsync: runsAsync,
            selectedRun: selectedRun,
            selectedRunId: _selectedRunId,
            onRunSelected: (runId) => setState(() => _selectedRunId = runId),
            type: _type,
            onTypeChanged: (type) {
              setState(() => _type = type);
              _reportDirty();
            },
            addressController: _addressController,
            reasonController: _reasonController,
            banner: _banner,
            bannerTone: _bannerTone,
          ),
        ),
        StickyActionBar(
          child: BaraedaButton(
            label: needsApproval ? '승인 요청 보내기' : '변경 신청하기',
            block: true,
            // 단추가 왜 꺼졌는지 단추 아래 글로 알려 준다.
            disabledReason: canSubmit ? null : _missingInput,
            onPressed: canSubmit ? _submit : null,
          ),
        ),
      ],
    );
  }
}

/// 신청이 실패했을 때 화면에 띄울 문구.
String _submitFailureMessage(Failure failure) => switch (failure) {
  ApiFailure(code: 'CHANGE_WINDOW_CLOSED') => '변경 신청 마감이 지났어요',
  ApiFailure(code: 'CHANGE_LIMIT_REACHED') => '이 회차는 변경 가능 횟수를 모두 사용했어요',
  ApiFailure(code: 'ADDRESS_VERIFICATION_FAILED') =>
    '주소를 확인할 수 없어요. 다시 입력해 주세요',
  ApiFailure(code: 'RUN_CANCELED') => runCanceledMessage,
  _ => failureMessage(failure, fallback: '신청을 처리하지 못했어요'),
};

/// 오늘은 서버 기본값(당일) 조회를 그대로 쓰고, 내일은 한국 시간 날짜를 `date` 로 보낸다.
AsyncValue<List<StudentRun>> _watchRuns(
  WidgetRef ref,
  String studentId,
  int dayOffset,
) {
  if (dayOffset == 0) return ref.watch(runsForStudentProvider(studentId));
  final date = koreaServiceDate(
    ref.watch(clockProvider).now(),
    plusDays: dayOffset,
  );
  return ref.watch(runsForStudentOnProvider((studentId, date)));
}

List<StudentRun> _readRuns(WidgetRef ref, String studentId, int dayOffset) {
  final runs = dayOffset == 0
      ? ref.read(runsForStudentProvider(studentId))
      : ref.read(
          runsForStudentOnProvider((
            studentId,
            koreaServiceDate(
              ref.read(clockProvider).now(),
              plusDays: dayOffset,
            ),
          )),
        );
  return runs.value ?? const [];
}
