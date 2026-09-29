import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/ui/confirm_dialog.dart';
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

  /// 끄기만 확인을 거친다(켜기는 바로) — 구간마다 결과가 달라 문구를 가른다(UF-P-04·05).
  /// 구간 판정은 서버가 준 `run_status`·`confirmed` 로만 한다(시각으로 계산하지 않는다).
  Future<void> _onSwitchChanged(bool value) async {
    if (value) return _toggle(true);
    final run = widget.run;
    final confirmed = await showConfirmDialog(
      context,
      title: '오늘 탑승을 끌까요?',
      body: switch (run.runStatus) {
        RunStatus.idle when !run.confirmed =>
          '바로 반영됩니다. 출발 30분 전까지는 다시 탑승으로 바꿀 수 있습니다.',
        RunStatus.idle || RunStatus.confirmed =>
          '출발 30분 전이 지나 학원 관리자의 승인이 필요합니다. '
              '승인 요청은 이 회차에서 1번만 보낼 수 있습니다.',
        RunStatus.moving || RunStatus.finished =>
          '운행이 시작돼 바로 반영되며 다시 탑승으로 바꿀 수 없습니다. '
              '노선은 바뀌지 않고 이 승하차지에는 정차하지 않습니다.',
      },
      confirmLabel: '탑승 끄기',
    );
    if (!confirmed || !mounted) return;
    await _toggle(false);
  }

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
          // 같은 코드가 끄기(이미 승하차 처리된 학생, Ruling 334)와 켜기(출발 30분 전부터
          // 탑승 복귀 불가)에서 뜻이 다르다.
          ApiFailure(code: 'CHANGE_WINDOW_CLOSED') =>
            value
                ? '출발 30분 전부터는 탑승으로 되돌릴 수 없습니다'
                : '이미 탑승 처리가 진행돼 앱에서는 바꿀 수 없습니다. 학원에 문의해 주세요',
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
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(BaraedaRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // UF-P-07 — "홈 · 실시간 운행 정보 → [지도 진입]". 이 배선이 없어서 지도 화면이
            // 만들어져 있는데도 도달할 수 없었다(2026-09-21). 지도로 가는 눌림은 카드 윗부분만
            // 받는다 — 스위치 줄까지 감싸면 전송 중(스위치 비활성)에 누른 손이 지도를 연다(R32 P4).
            InkWell(
              onTap: () => context.push(AppRoutes.liveMap),
              borderRadius: BorderRadius.circular(BaraedaRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${run.direction.label} · ${run.busNo}',
                          style: BaraedaTypography.bodyLg,
                        ),
                        BaraedaStatusPill(
                          status: status.status,
                          label: status.label,
                        ),
                      ],
                    ),
                    const SizedBox(height: BaraedaSpacing.space1),
                    Text(
                      '${_formatTime(run.departTime)} 출발 · ${run.stop.name}',
                    ),
                    if (_untilConfirm(run, ref.watch(clockProvider).now())
                        case final left?)
                      Text('확정까지 $left', style: BaraedaTypography.bodySm),
                  ],
                ),
              ),
            ),
            if (widget.canToggle || _banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  BaraedaSpacing.cardPadding,
                  0,
                  BaraedaSpacing.cardPadding,
                  BaraedaSpacing.cardPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.canToggle)
                      BaraedaSwitch(
                        checked: run.riding,
                        label: '오늘 탑승',
                        sublabel: '잔여 변경 ${run.changeQuotaLeft}회',
                        onChanged: _submitting ? null : _onSwitchChanged,
                      ),
                    if (_banner != null) ...[
                      const SizedBox(height: BaraedaSpacing.space2),
                      AlertBanner(tone: _bannerTone, body: _banner),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 확정(출발 30분 전)까지 남은 시간 문구 — 확정 전(`idle`·미확정)이고 아직 남았을 때만.
String? _untilConfirm(StudentRun run, DateTime now) {
  if (run.runStatus != RunStatus.idle || run.confirmed) return null;
  final left = run.departTime
      .subtract(const Duration(minutes: 30))
      .difference(now);
  if (left <= Duration.zero) return null;
  if (left.inMinutes < 1) return '1분 미만';
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}

({BaraedaStatus status, String label}) _statusFor(StudentRun run) {
  return switch (run.riderStatus) {
    RiderStatus.boarded || RiderStatus.alighted => (
      status: BaraedaStatus.boarded,
      label: run.riderStatus == RiderStatus.boarded ? '탑승 완료' : '하차 완료',
    ),
    // ⚠ `absent`(미등원)와 `no_show`(미승차)를 합치지 않는다 — `FEATURE_SPEC C-02`
    // 가 "반드시 구분" 을 명시한다. 학부모에게 둘은 전혀 다른 일이다 —
    // 미등원은 **내가 직접 껐다**(정상), 미승차는 **버스가 왔는데 안 나왔다**(사고).
    // 색도 사양이 가른다(§3 상태표) — 미등원 스톤 · 미승차 레드.
    RiderStatus.absent => (status: BaraedaStatus.idle, label: '미등원'),
    RiderStatus.noShow => (status: BaraedaStatus.missed, label: '미승차'),
    RiderStatus.waiting =>
      run.runStatus == RunStatus.moving
          ? (status: BaraedaStatus.moving, label: '이동 중')
          : (status: BaraedaStatus.idle, label: '운행 전'),
  };
}

/// 서버가 주는 시각은 **UTC 순간**이다(`…Z`). `DateTime.parse` 는 오프셋이
/// 붙은 문자열을 UTC `DateTime` 으로 돌려주므로, 벽시계로 읽으려면 기기
/// 표준시로 옮겨야 한다 — 안 옮기면 KST 에서 **9시간 이른 시각**이 나온다.
String _formatTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
