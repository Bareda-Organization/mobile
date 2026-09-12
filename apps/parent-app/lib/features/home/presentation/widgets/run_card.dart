import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';

/// 회차 1건 카드 — §3.5 조회 값 표시 + (학부모만) §3.6 등원 여부 토글.
///
/// **ETA·탑승 인원은 표시하지 않는다(C-08)** — [StudentRun] 자체에 그
/// 필드가 부재하므로 이 위젯도 추가할 수 없다.
class RunCard extends ConsumerStatefulWidget {
  const RunCard({
    required this.studentId,
    required this.run,
    required this.canToggle,
    super.key,
  });

  final String studentId;
  final StudentRun run;

  /// 학부모만 true(`roleCapabilitiesProvider.canToggleAttendance`).
  final bool canToggle;

  @override
  ConsumerState<RunCard> createState() => _RunCardState();
}

class _RunCardState extends ConsumerState<RunCard> {
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  Future<void> _toggle(bool value) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _banner = null;
    });

    final repository = ref.read(runRepositoryProvider);
    try {
      final result = await repository.updateIntent(
        widget.studentId,
        widget.run.runId,
        riding: value,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _banner = switch (result.result) {
          RunIntentApplyResult.applied => null,
          RunIntentApplyResult.pendingApproval =>
            '기사·동승자 승인 대기 중입니다 (마감 ${result.deadlineAt}).',
          RunIntentApplyResult.appliedNoReroute => '운행이 시작돼 노선은 바뀌지 않고 반영됐습니다.',
        };
        _bannerTone = AlertTone.info;
      });
      ref.invalidate(runsForStudentProvider(widget.studentId));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(code: 'CHANGE_LIMIT_REACHED') =>
            '이 회차는 변경 가능 횟수를 모두 사용했습니다',
          ApiFailure(code: 'CHANGE_WINDOW_CLOSED') => '운행 중에는 이 변경을 되돌릴 수 없습니다',
          ApiFailure(:final message) => message,
          _ => '변경을 처리하지 못했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final status = _statusFor(run);

    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.cardGap),
      child: Container(
        padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(BaraedaRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${run.direction.label} · ${run.busNo}번',
                  style: BaraedaTypography.bodyLg,
                ),
                BaraedaStatusPill(status: status.status, label: status.label),
              ],
            ),
            const SizedBox(height: BaraedaSpacing.space1),
            Text('${_formatTime(run.departTime)} 출발 · ${run.stop.name}'),
            if (widget.canToggle) ...[
              const SizedBox(height: BaraedaSpacing.space2),
              BaraedaSwitch(
                checked: run.riding,
                label: '오늘 탑승',
                sublabel: '잔여 변경 ${run.changeQuotaLeft}회',
                onChanged: _submitting ? null : _toggle,
              ),
            ],
            if (_banner != null) ...[
              const SizedBox(height: BaraedaSpacing.space2),
              AlertBanner(tone: _bannerTone, body: _banner),
            ],
          ],
        ),
      ),
    );
  }
}

({BaraedaStatus status, String label}) _statusFor(StudentRun run) {
  return switch (run.riderStatus) {
    RiderStatus.boarded || RiderStatus.alighted => (
      status: BaraedaStatus.boarded,
      label: run.riderStatus == RiderStatus.boarded ? '탑승 완료' : '하차 완료',
    ),
    RiderStatus.absent || RiderStatus.noShow => (
      status: BaraedaStatus.missed,
      label: '미탑승',
    ),
    RiderStatus.waiting => run.runStatus == RunStatus.moving
        ? (status: BaraedaStatus.moving, label: '이동 중')
        : (status: BaraedaStatus.idle, label: '운행 전'),
  };
}

String _formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
