import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';

/// RunEndScreen — 운행 종료 요약 + §4.13 현장 상황 보고 (M-11).
///
/// §4.10 이 명시하는 "전용 종료 API 부재" 때문에, 이 화면은 종료 상태를
/// 서버에서 다시 조회하지 않고 DriveMode 의 §4.5 도착 처리 응답
/// ([lastArriveResultProvider])을 그대로 재구성해 보여준다. 보고 작성
/// (§4.13)은 기사·동승자 둘 다 가능해 role_policy.dart 에 capability 를
/// 두지 않았다(`ReportsRepository` 주석과 같은 판단).
///
/// 동승자는 도착 처리 결과가 없어도 명단 화면의 `[예외 보고]` 로 이 화면에 들어온다(R32 M3) —
/// 그때는 종료 요약 대신 "예외 보고" 화면이 되고, 보호자 부재 대상 학생은 명단에서 만든다.
///
/// §4.11(변경 확인, M-04)은 이 화면이 아니라 StopRoster 의 몫이다
/// (`roster_screen.dart` · `USER_FLOWS.md UF-D-02`) — 종료 시점의 변경
/// 확인이 아니라 확정 후 운행 중 변경 발생 시 확인하는 흐름이라 화면이
/// 다르다. 이전 판단은 여기를 "범위 밖" 으로 잘못 적었던 것을 정정한다.
class RunEndScreen extends ConsumerStatefulWidget {
  const RunEndScreen({super.key});

  @override
  ConsumerState<RunEndScreen> createState() => _RunEndScreenState();
}

class _RunEndScreenState extends ConsumerState<RunEndScreen> {
  ReportType _type = ReportType.guardianAbsent;
  final _memoController = LimitedTextController();
  String? _selectedRiderId;

  bool _submitting = false;
  String? _errorMessage;
  ReportResult? _result;

  static const _typeOptions = [
    BaraedaSegmentedOption('guardian_absent', label: '보호자 부재'),
    BaraedaSegmentedOption('road_block', label: '도로 통제'),
    BaraedaSegmentedOption('vehicle_issue', label: '차량 문제'),
    BaraedaSegmentedOption('etc', label: '기타'),
  ];

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _submit(String runId) async {
    final memo = _memoController.text.trim();
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
              type: _type,
              memo: memo,
              riderId: _type == ReportType.guardianAbsent
                  ? _selectedRiderId
                  : null,
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

  /// 접수 시각(기기 시간대) — 한 줄 80자 제한 안에 두려고 뺐다.
  String get _reportedTime =>
      DateFormat('HH:mm:ss').format(_result!.reportedAt.toLocal());

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    // 도착 응답 스냅샷은 그 회차의 것일 때만 쓴다 — 마지막 도착 처리가 스냅샷과 함께
    // [transmissionEndedRunIdProvider] 를 같은 회차로 채운다. 다른 회차의 종료 화면을 열면 앞 회차의
    // 도착 시각·하차 대기가 그대로 나오던 것을 막는다(F06-14).
    final snapshot = ref.watch(lastArriveResultProvider);
    final termination =
        snapshot != null && ref.watch(transmissionEndedRunIdProvider) == runId
        ? snapshot
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(termination == null ? '예외 보고' : '운행 종료'),
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (termination != null) ...[
                    _buildSummary(termination),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '현장 상황 보고',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildReportForm(runId, termination),
                ],
              ),
            ),
    );
  }

  /// 종료 안내 — 도착 시각만 스냅샷([termination])에서 가져오고, 하차 대기 인원·종료 여부는 지금의 명단·
  /// 회차 목록에서 읽는다. 동승자가 하차 처리를 마쳐 회차가 끝나도 "N명 남음" 이 그대로 남던 것을 막는다(F06-14).
  Widget _buildSummary(ArriveStopResult termination) {
    final arrivedLabel = DateFormat(
      'HH:mm',
    ).format(termination.arrivedAt.toLocal());
    final finished =
        ref.watch(selectedManagerRunProvider)?.runStatus == RunStatus.finished;
    if (!termination.finishPending || finished) {
      return AlertBanner(
        tone: AlertTone.boarded,
        body: '$arrivedLabel 운행이 종료됐습니다',
      );
    }
    final waiting = _reportTargets(termination).length;
    return AlertBanner(
      tone: AlertTone.moving,
      body:
          '$arrivedLabel 최종 지점 도착 — 하차 대기 $waiting명 '
          '남음(전원 하차해야 운행이 종료됩니다)',
    );
  }

  /// 보호자 부재 보고의 대상 학생 — **지금** 명단에서 탑승 중인 학생이다. 도착 결과가 있으면(하원 종료
  /// 보류) 탑승 중인 전원, 없으면(동승자가 명단에서 들어온 경우) 그중 혼자 귀가할 수 없는 학생이다
  /// (§4.13 · A-10). 명단을 아직 못 받았으면 도착 응답의 하차 대기 명단으로 대신한다.
  List<({String riderId, String name})> _reportTargets(
    ArriveStopResult? termination,
  ) {
    final roster = ref.watch(rosterProvider).value;
    if (roster == null) {
      return [
        for (final rider in termination?.remaining ?? const <RemainingRider>[])
          (riderId: rider.riderId, name: rider.name),
      ];
    }
    return [
      for (final stop in roster.stops)
        for (final student in stop.students)
          if (student.status == RiderStatus.boarded &&
              (termination != null || !student.canGoAlone))
            (riderId: student.riderId, name: student.name),
    ];
  }

  Widget _buildReportForm(String runId, ArriveStopResult? termination) {
    final remaining = _reportTargets(termination);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: _errorMessage),
          const SizedBox(height: 12),
        ],
        if (_result != null) ...[
          AlertBanner(
            tone: AlertTone.boarded,
            body: '보고가 접수됐습니다 ($_reportedTime)',
          ),
          const SizedBox(height: 12),
        ],
        BaraedaSegmentedControl(
          options: _typeOptions,
          value: _type.wireValue,
          block: true,
          // 칸이 4개라 좁은 폭·큰 글자에서 낱말 중간에서 끊긴다 — 낱말 단위로 줄을 바꾼다(R46).
          wrapByWord: true,
          onChanged: _submitting
              ? null
              : (value) => setState(() {
                  _type = ReportType.values.firstWhere(
                    (type) => type.wireValue == value,
                  );
                  if (_type != ReportType.guardianAbsent) {
                    _selectedRiderId = null;
                  }
                }),
        ),
        if (_type == ReportType.guardianAbsent) ...[
          const SizedBox(height: 12),
          BaraedaSelect(
            label: '대상 학생 (하차 대기 명단)',
            options: [
              for (final rider in remaining)
                BaraedaSelectOption(rider.riderId, label: rider.name),
            ],
            value: _selectedRiderId,
            enabled: !_submitting && remaining.isNotEmpty,
            onChanged: (value) => setState(() => _selectedRiderId = value),
          ),
          // 대상이 없으면 선택 칸이 왜 꺼져 있는지 알린다(R32 M11).
          if (remaining.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: WordWrapText(
                '보호자 부재로 보고할 학생이 없습니다 — 혼자 귀가할 수 없는 학생이 탑승 중일 때만 고를 수 있습니다',
              ),
            ),
        ],
        const SizedBox(height: 12),
        BaraedaTextarea(
          label: '상황 메모 (필수)',
          hint: '무슨 일이 있었는지 적어 주세요 · $freeTextPrivacyNotice',
          enabled: !_submitting,
          controller: _memoController,
        ),
        const SizedBox(height: 20),
        BaraedaButton(
          label: '보고 제출',
          size: BaraedaButtonSize.lg,
          // 접수된 뒤에는 끈다 — 다시 누르면 같은 보고가 한 번 더 관계자에게 통지된다(R32 M11).
          onPressed: (_submitting || _result != null)
              ? null
              : () => _submit(runId),
        ),
      ],
    );
  }
}
