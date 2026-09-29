import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/time/service_date.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';

/// 회차 선택 목록에 쓰는 표시 문구 — `방향 · 버스번호번`. 위젯 시험이
/// 이 문구를 직접 적어 두면 라벨 문구(`RunDirection.label`)가 바뀔 때
/// 무관한 사유로 조용히 깨진다 — 여기 노출해 시험이 값으로 참조하게 한다.
// `bus_no` 는 호차 **이름 그 자체**다(`ERD bus.bus_no varchar(20)` · 시드 '1호차').
// 단위를 덧붙이면 "1호차번" 이 된다.
String runOptionLabel(StudentRun run) =>
    '${run.direction.label} · ${run.busNo}';

/// §3.8·§3.9 — 일일 변경 신청. 날짜(오늘·내일, 한국 시간)를 고르면 `core/runs` 의
/// §3.5 조회가 그날 회차를 주고, 그중 하나를 대상으로 신청한다.
class ChangeRequestPanel extends ConsumerStatefulWidget {
  const ChangeRequestPanel({required this.studentId, super.key});

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
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.boarded;
        _banner = result.result == 'pending_approval'
            ? '승인 대기로 접수됐습니다${deadlineNote(result.deadlineAt)}.'
            : '변경 신청이 반영됐습니다.';
      });
      // 접수한 내용은 더 이상 저장 안 된 입력이 아니다 — 비워서 같은 내용의 재접수도 막는다.
      _addressController.clear();
      _reasonController.clear();
      _reportDirty();
      ref.invalidate(changeRequestsProvider(widget.studentId));
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
          ApiFailure(:final message) => message,
          _ => '신청을 처리하지 못했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 오늘은 서버 기본값(당일) 조회를 그대로 쓰고, 내일은 한국 시간 날짜를 `date` 로 보낸다.
    final runsAsync = _dayOffset == 0
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
    final requestsAsync = ref.watch(changeRequestsProvider(widget.studentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDayPicker(),
        const SizedBox(height: BaraedaSpacing.space2),
        runsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const AlertBanner(
            tone: AlertTone.missed,
            body: '회차를 불러오지 못했습니다',
          ),
          data: (runs) {
            if (runs.isEmpty) {
              return const Text('그날 운행이 아직 없습니다');
            }
            final runOptions = runs
                .map((r) => (r.runId, runOptionLabel(r)))
                .toList();
            return _buildForm(runOptions);
          },
        ),
        const SizedBox(height: BaraedaSpacing.space6),
        const Text('신청 이력', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space2),
        requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const AlertBanner(
            tone: AlertTone.missed,
            body: '신청 이력을 불러오지 못했습니다',
          ),
          data: _buildHistory,
        ),
      ],
    );
  }

  /// 신청할 날짜 — 오늘·내일 두 가지. 날짜를 바꾸면 앞서 고른 회차는 다른 날 것이라 비운다.
  Widget _buildDayPicker() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('오늘')),
        ButtonSegment(value: 1, label: Text('내일')),
      ],
      selected: {_dayOffset},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => setState(() {
        _dayOffset = selection.first;
        _selectedRunId = null;
      }),
    );
  }

  Widget _buildForm(List<(String, String)> runOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSelect(
          label: '대상 회차',
          value: _selectedRunId,
          options: runOptions
              .map((o) => BaraedaSelectOption(o.$1, label: o.$2))
              .toList(),
          onChanged: (value) => setState(() => _selectedRunId = value),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSelect(
          label: '신청 종류',
          value: _type.wireValue,
          options: const [
            BaraedaSelectOption('cancel', label: '탑승 취소'),
            BaraedaSelectOption('relocate', label: '승하차지 변경'),
          ],
          onChanged: (value) {
            setState(
              () => _type = ChangeRequestType.fromWireValue(value ?? 'cancel'),
            );
            _reportDirty();
          },
        ),
        if (_type == ChangeRequestType.relocate) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          BaraedaInput(label: '변경할 주소', controller: _addressController),
        ],
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaTextarea(label: '사유(선택)', controller: _reasonController),
        const SizedBox(height: BaraedaSpacing.space2),
        if (_banner != null) ...[
          AlertBanner(tone: _bannerTone, body: _banner),
          const SizedBox(height: BaraedaSpacing.space2),
        ],
        // 버튼이 왜 눌리지 않는지 알려 준다.
        if (_missingInput != null) ...[
          Text(_missingInput!, style: BaraedaTypography.bodySm),
          const SizedBox(height: BaraedaSpacing.space2),
        ],
        BaraedaButton(
          label: '변경 신청하기',
          onPressed: (_submitting || _missingInput != null) ? null : _submit,
        ),
      ],
    );
  }

  Widget _buildHistory(ChangeRequestPage page) {
    if (page.items.isEmpty) {
      return const EmptyState(title: '신청 이력이 없습니다');
    }
    return Column(
      children: page.items
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.type == ChangeRequestType.cancel ? '탑승 취소' : '승하차지 변경',
              ),
              subtitle: item.rejectReason != null
                  ? Text('반려: ${item.rejectReason}')
                  : null,
              trailing: BaraedaBadge(
                label: _statusLabel(item.status),
                tone: _statusTone(item.status),
              ),
            ),
          )
          .toList(),
    );
  }

  String _statusLabel(ChangeRequestStatus status) => switch (status) {
    ChangeRequestStatus.pending => '대기',
    ChangeRequestStatus.approved => '승인',
    ChangeRequestStatus.rejected => '반려',
    ChangeRequestStatus.autoRejected => '자동 반려',
  };

  BaraedaBadgeTone _statusTone(ChangeRequestStatus status) => switch (status) {
    ChangeRequestStatus.pending => BaraedaBadgeTone.amber,
    ChangeRequestStatus.approved => BaraedaBadgeTone.brand,
    ChangeRequestStatus.rejected ||
    ChangeRequestStatus.autoRejected => BaraedaBadgeTone.red,
  };
}
