import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/confirm_dialog.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/core/ui/minute_ticker.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';

/// 회차 1건 카드 — §3.5 조회 값 표시 + (학부모만) §3.6 등원 여부 토글.
///
/// **ETA·탑승 인원은 표시하지 않는다(C-08)** — [StudentRun] 자체에 그
/// 필드가 부재하므로 이 위젯도 추가할 수 없다.
///
/// [date] 가 있으면 그날(내일) 회차 카드다 — 문구가 '내일 탑승' 이 되고, 확정까지 남은 시간
/// (오늘 출발 판정용)과 지도 진입(운행 중에만 의미)은 뺀다(R34 P1).
class RunCard extends ConsumerStatefulWidget {
  const new({
    required this.studentId,
    required this.run,
    required this.canToggle,
    this.date,
    this.isApprovalPending = false,
    this.approvalDeadlineAt,
    super.key,
  });

  final String studentId;
  final StudentRun run;

  /// 오늘이면 null, 내일 회차면 그 운행 날짜(한국 시간) — 쓰기 뒤 어느 목록을 다시 받을지 가른다.
  final DateTime? date;

  /// 학부모만 true(`roleCapabilitiesProvider.canToggleAttendance`).
  final bool canToggle;

  /// 이 회차에 ②구간 변경 신청이 관리자 승인을 기다리는 중인가 — 홈이 §3.9 신청 이력에서 가려 넘긴다.
  final bool isApprovalPending;

  /// 그 승인 대기 신청의 마감 — 서버가 준 `deadline_at` 이다(`Ruling 870`). 없으면 남은 시간을 보이지 않는다.
  final DateTime? approvalDeadlineAt;

  @override
  ConsumerState<RunCard> createState() => _RunCardState();
}

class _RunCardState extends ConsumerState<RunCard> {
  String get _dayWord => widget.date == null ? '오늘' : '내일';

  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// 탑승 취소(끄기)만 확인을 거친다(켜기는 바로) — 구간마다 결과가 달라 문구를 가른다(UF-P-04·05).
  /// 구간 판정은 서버와 같은 [changeZoneOf] 한 곳이다(`Ruling 870`).
  Future<void> _onSwitchChanged(bool value) async {
    if (value) return await _toggle(true);
    final run = widget.run;
    final confirmAt = formatClock(run.departTime.subtract(confirmLead));
    final zone = changeZoneOf(run, ref.read(clockProvider).now());
    // 구간마다 결과가 달라 문구와 확인 단추를 가른다(시안 `cancel-ride` · `--approval` · `--moving`).
    // ②구간의 단추는 취소가 아니라 "요청" 이라 위험색이 아니다 — 취소가 즉시 되는 줄 아는 오해를 막는다(P2).
    final needsApproval = zone == ChangeZone.approval;
    final confirmed = await showConfirmDialog(
      context,
      title: '$_dayWord 탑승을 취소할까요?',
      body: switch (zone) {
        ChangeZone.immediate =>
          '바로 반영돼요. 출발 30분 전($confirmAt)까지는 다시 탑승으로 바꿀 수 있어요.',
        ChangeZone.approval =>
          '출발 30분 전이 지나 학원 관리자의 승인이 필요해요. '
              '승인 요청은 이 회차에서 1번만 보낼 수 있고, 운행이 시작되기 전까지 승인되지 않으면 자동으로 반려돼요.',
        ChangeZone.closed =>
          '승인 요청을 받는 시간이 지나 바로 반영되고 다시 탑승으로 바꿀 수 없어요. '
              '노선은 바뀌지 않고, ${run.stop.name}에는 정차하지 않아요.',
      },
      confirmLabel: needsApproval ? '승인 요청 보내기' : '탑승 취소',
      danger: !needsApproval,
      // 확인 버튼이 "탑승 취소" 라 창을 닫는 쪽을 "취소" 로 두면 두 버튼이 같은 말이 된다.
      cancelLabel: '닫기',
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
            '학원 관리자 승인 대기 중입니다${deadlineNote(result.deadlineAt)}.',
          RunIntentApplyResult.appliedNoReroute => '운행이 시작돼 노선은 바뀌지 않고 반영됐습니다.',
        };
        _bannerTone = AlertTone.info;
      });
      final date = widget.date;
      ref
        ..invalidate(
          date == null
              ? runsForStudentProvider(widget.studentId)
              : runsForStudentOnProvider((widget.studentId, date)),
        )
        // F05-02 — ② 구간 접수는 신청 이력·처리 대기 배지에 나타난다.
        ..invalidate(changeRequestsProvider(widget.studentId));
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
          ApiFailure(code: 'RUN_CANCELED') => runCanceledMessage,
          _ => failureMessage(failure, fallback: '변경을 처리하지 못했습니다'),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final status = runStatusChip(run);

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
              onTap: widget.date == null
                  ? () => context.push(AppRoutes.liveMap)
                  : null,
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
                      '${formatClock(run.departTime)} 출발 · ${run.stop.name}',
                    ),
                    if (widget.date == null)
                      MinuteTicker(
                        builder: (context, now) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (untilConfirm(run, now) case final left?)
                              WordWrapText(
                                '확정까지 $left',
                                style: BaraedaTypography.bodySm,
                              ),
                          ],
                        ),
                      ),
                    if (widget.isApprovalPending)
                      MinuteTicker(
                        builder: (context, now) => WordWrapText(
                          _approvalWaitText(widget.approvalDeadlineAt, now),
                          style: BaraedaTypography.bodySm,
                        ),
                      ),
                    // UF-P-07 진입 표시 — 카드 전체가 눌리는데 그 표시가 없어
                    // 지도로 가는 길을 못 찾았다(R46 B2 #11).
                    // 지도에 볼 것이 있는 운행 중 오늘 카드에만 붙인다.
                    if (widget.date == null &&
                        run.runStatus == RunStatus.moving)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: BaraedaSpacing.space2,
                        ),
                        child: Text(
                          '실시간 위치 보기 ›',
                          style: BaraedaTypography.bodySm.copyWith(
                            color: context.colors.accentPrimary,
                          ),
                        ),
                      ),
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
                      MinuteTicker(
                        builder: (context, now) => BaraedaSwitch(
                          checked: run.riding,
                          label: '$_dayWord 탑승',
                          // ①은 횟수 제한이 없고 ③은 신청할 수 없다 —
                          // ②구간에서만 뜻이 있다(Ruling 874).
                          sublabel:
                              changeZoneOf(run, now) == ChangeZone.approval
                              ? '잔여 변경 ${run.changeQuotaLeft}회'
                              : null,
                          onChanged: _submitting ? null : _onSwitchChanged,
                        ),
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

/// ②구간 변경 신청은 마감까지 승인되지 않으면 서버가 자동 거절한다
/// (`FEATURE_SPEC C-04` · `Ruling 870`) — 마감은 서버가 준 `deadline_at` 이고, 그때까지
/// 남은 시간이 카운트다운이다. 마감을 모르면 "승인 대기" 만 보인다.
String _approvalWaitText(DateTime? deadlineAt, DateTime now) {
  final left = deadlineAt?.difference(now);
  return left == null || left <= Duration.zero
      ? '승인 대기'
      : '승인 대기 · 마감까지 ${formatRemaining(left)}';
}
