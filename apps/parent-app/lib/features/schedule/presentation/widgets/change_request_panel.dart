import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';

/// 회차 선택 목록에 쓰는 표시 문구 — `방향 · 버스번호번`. 위젯 시험이
/// 이 문구를 직접 적어 두면 라벨 문구(`RunDirection.label`)가 바뀔 때
/// 무관한 사유로 조용히 깨진다 — 여기 노출해 시험이 값으로 참조하게 한다.
// `bus_no` 는 호차 **이름 그 자체**다(`ERD bus.bus_no varchar(20)` · 시드 '1호차').
// 단위를 덧붙이면 "1호차번" 이 된다.
String runOptionLabel(StudentRun run) => '${run.direction.label} · ${run.busNo}';

/// §3.8·§3.9 — 일일 변경 신청. 회차 선택은 `core/runs` 의 §3.5 조회 결과를
/// 그대로 쓴다(변경 신청은 반드시 오늘의 특정 회차를 대상으로 한다).
class ChangeRequestPanel extends ConsumerStatefulWidget {
  const ChangeRequestPanel({required this.studentId, super.key});

  final String studentId;

  @override
  ConsumerState<ChangeRequestPanel> createState() =>
      _ChangeRequestPanelState();
}

class _ChangeRequestPanelState extends ConsumerState<ChangeRequestPanel> {
  final _addressController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _selectedRunId;
  ChangeRequestType _type = ChangeRequestType.cancel;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  @override
  void dispose() {
    _addressController.dispose();
    _reasonController.dispose();
    super.dispose();
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
            ? '승인 대기로 접수됐습니다 (마감 ${result.deadlineAt}).'
            : '변경 신청이 반영됐습니다.';
      });
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
    final runsAsync = ref.watch(runsForStudentProvider(widget.studentId));
    final requestsAsync = ref.watch(changeRequestsProvider(widget.studentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        runsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const AlertBanner(
            tone: AlertTone.missed,
            body: '오늘 회차를 불러오지 못했습니다',
          ),
          data: (runs) {
            if (runs.isEmpty) {
              return const Text('오늘 신청 가능한 회차가 없습니다');
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
          onChanged: (value) => setState(
            () => _type = ChangeRequestType.fromWireValue(value ?? 'cancel'),
          ),
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
        BaraedaButton(
          label: '변경 신청하기',
          onPressed: (_submitting || _selectedRunId == null) ? null : _submit,
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
