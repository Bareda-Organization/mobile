import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';

/// 현장 상황 보고(§4.13, M-14) — 도로 통제 · 차량 문제 · 기타([guardianAbsent] 가 아닐 때, 시안
/// `report`) 또는
/// 보호자 부재(학생 한 명을 골라 보고, 시안 `guardian-absent`).
///
/// 보고는 학원 관계자에게만 전달된다 — 학부모에게 알려야 하면 동승자가 지연 알림을 보낸다. 접수된 뒤에는 제출
/// 단추를 꺼 같은 보고가 두 번 나가지 않게 한다(R32 M11).
class ReportScreen extends ConsumerStatefulWidget {
  const new({super.key, this.guardianAbsent = false});

  /// 보호자 부재 보고 — 학생 선택이 필수다(`riderId`).
  final bool guardianAbsent;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportType _type = ReportType.roadBlock;
  final _memoController = LimitedTextController();
  String? _selectedRiderId;

  bool _submitting = false;
  String? _errorMessage;
  ReportResult? _result;

  static const _typeOptions = [
    BaraedaSegmentedOption('road_block', label: '도로 통제'),
    BaraedaSegmentedOption('vehicle_issue', label: '차량 문제'),
    BaraedaSegmentedOption('etc', label: '기타'),
  ];

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  ReportType get _effectiveType =>
      widget.guardianAbsent ? ReportType.guardianAbsent : _type;

  Future<void> _submit(String runId) async {
    final memo = _memoController.text.trim();
    if (widget.guardianAbsent && _selectedRiderId == null) {
      setState(() => _errorMessage = '어느 학생인지 골라 주세요');
      return;
    }
    if (memo.isEmpty) {
      setState(() => _errorMessage = '상황 메모를 입력해 주세요');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(reportsRepositoryProvider)
          .submitReport(
            runId: runId,
            request: ReportRequest(
              type: _effectiveType,
              memo: memo,
              riderId: widget.guardianAbsent ? _selectedRiderId : null,
            ),
          );
      if (!mounted) return;
      setState(() => _result = result);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 보호자 부재로 보고할 수 있는 학생 — 버스에 타고 있고 혼자 귀가할 수 없는 학생. 마지막 도착 응답의 하차 대기
  /// 명단이 있으면(종료 직후) 그것을 쓴다.
  List<({String riderId, String name, String meta})> _targets(
    ArriveStopResult? termination,
  ) {
    final roster = ref.watch(rosterProvider).value;
    if (roster == null) {
      return [
        for (final rider in termination?.remaining ?? const <RemainingRider>[])
          (riderId: rider.riderId, name: rider.name, meta: ''),
      ];
    }
    return [
      for (final stop in roster.stops)
        for (final student in stop.students)
          if (student.status == RiderStatus.boarded &&
              (termination != null || !student.canGoAlone))
            (
              riderId: student.riderId,
              name: student.name,
              meta: [
                student.className,
                stop.name,
              ].whereType<String>().join(' · '),
            ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final roster = ref.watch(rosterProvider).value;
    final snapshot = ref.watch(lastArriveResultProvider);
    // 도착 응답 스냅샷은 그 회차의 것일 때만 쓴다(F06-14).
    final termination =
        snapshot != null && ref.watch(transmissionEndedRunIdProvider) == runId
        ? snapshot
        : null;
    final colors = context.colors;
    final targets = widget.guardianAbsent
        ? _targets(termination)
        : const <({String riderId, String name, String meta})>[];

    return Scaffold(
      appBar: ManagerHeader(
        title: widget.guardianAbsent ? '보호자 부재 보고' : '현장 상황 보고',
        subtitle: widget.guardianAbsent && roster != null
            ? '${roster.busNo} · ${directionLabel(roster.direction)}'
            : null,
      ),
      body: runId == null
          ? const EmptyState(
              title: '선택된 운행이 없어요',
              body: '회차 탭에서 오늘 운행을 골라 주세요.',
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_errorMessage != null) ...[
                        AlertBanner(
                          tone: AlertTone.missed,
                          body: _errorMessage,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_result != null) ...[
                        AlertBanner(
                          tone: AlertTone.boarded,
                          title: '보고가 접수됐어요',
                          body: hhmm(_result!.reportedAt),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!widget.guardianAbsent) ...[
                        const Text('어떤 상황이에요?', style: BaraedaTypography.label),
                        const SizedBox(height: 8),
                        BaraedaSegmentedControl(
                          options: _typeOptions,
                          value: _type.wireValue,
                          block: true,
                          wrapByWord: true,
                          onChanged: _submitting
                              ? null
                              : (value) => setState(
                                  () => _type = ReportType.values.firstWhere(
                                    (type) => type.wireValue == value,
                                  ),
                                ),
                        ),
                      ] else ...[
                        const Text('어느 학생이에요?', style: BaraedaTypography.label),
                        const SizedBox(height: 8),
                        if (targets.isEmpty)
                          const WordWrapText(
                            '보호자 부재로 보고할 학생이 없어요. 혼자 귀가할 수 없는 학생이 '
                            '탑승 중일 때만 고를 수 있어요.',
                          )
                        else
                          BaraedaListGroup(
                            children: [
                              for (final target in targets)
                                BaraedaListRow(
                                  title: target.name,
                                  titleIsPersonName: true,
                                  subtitle: target.meta.isEmpty
                                      ? null
                                      : target.meta,
                                  trailing: BaraedaIcon(
                                    _selectedRiderId == target.riderId
                                        ? 'circle-check'
                                        : 'check',
                                    color: _selectedRiderId == target.riderId
                                        ? colors.accentPrimary
                                        : colors.borderControl,
                                  ),
                                  onTap: _submitting
                                      ? null
                                      : () => setState(
                                          () =>
                                              _selectedRiderId = target.riderId,
                                        ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '버스에 타고 있고 혼자 귀가할 수 없는 학생만 나와요.',
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      BaraedaTextarea(
                        label: '상황 메모 (필수)',
                        hint: '무슨 일이 있었는지 적어 주세요 · $freeTextPrivacyNotice',
                        enabled: !_submitting,
                        controller: _memoController,
                      ),
                      const SizedBox(height: 12),
                      AlertBanner(
                        tone: AlertTone.info,
                        body: widget.guardianAbsent
                            ? '제출하면 학원 관계자에게 바로 전달되고, 이후는 관계자가 판단해요.'
                            : '보고는 학원 관계자에게 전달돼요. 학부모에게 알려야 하면 '
                                  '동승자가 지연 알림을 보내요.',
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.bgBase,
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: BaraedaButton(
                        label: '보고 제출',
                        size: BaraedaButtonSize.xl,
                        block: true,
                        // 접수된 뒤에는 끈다 — 다시 누르면 같은 보고가 한 번 더 관계자에게 통지된다(R32 M11).
                        onPressed: (_submitting || _result != null)
                            ? null
                            : () => _submit(runId),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
