import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
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
  final _memoController = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final termination = ref.watch(lastArriveResultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('운행 종료')),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSummary(termination),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
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

  Widget _buildSummary(ArriveStopResult? termination) {
    if (termination == null) {
      // AlertTone.info 는 쓰지 않는다 — baraeda_ui 의 아이콘 매핑표
      // (packages/baraeda_ui/lib/widgets/core/icon.dart)에 'info' 글리프가
      // 없어 디버그 모드에서 단언 실패로 렌더링이 죽는다(F2 의
      // pending_approval_screen.dart 도 같은 값을 써서 이미 잠재돼 있음 —
      // baraeda_ui 는 범위 밖이라 그대로 두고 이 화면만 우회한다).
      return const Center(
        child: Text('종료 정보가 없습니다 — 운행 모드에서 최종 지점 도착 처리를 마치면 이 화면으로 이동합니다'),
      );
    }
    final arrivedLabel = DateFormat('HH:mm').format(termination.arrivedAt.toLocal());
    if (termination.finishPending) {
      return AlertBanner(
        tone: AlertTone.moving,
        body:
            '$arrivedLabel 최종 지점 도착 — 하차 대기 ${termination.remaining.length}명 '
            '남음(전원 하차해야 운행이 종료됩니다)',
      );
    }
    return AlertBanner(
      tone: AlertTone.boarded,
      body: '$arrivedLabel 운행이 종료됐습니다',
    );
  }

  Widget _buildReportForm(String runId, ArriveStopResult? termination) {
    final remaining = termination?.remaining ?? const <RemainingRider>[];

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
            body:
                '보고가 접수됐습니다 '
                '(${DateFormat('HH:mm:ss').format(_result!.reportedAt.toLocal())})',
          ),
          const SizedBox(height: 12),
        ],
        BaraedaSegmentedControl(
          options: _typeOptions,
          value: _type.wireValue,
          block: true,
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
        ],
        const SizedBox(height: 12),
        BaraedaTextarea(
          label: '상황 메모',
          hint: '무슨 일이 있었는지 적어 주세요',
          enabled: !_submitting,
          controller: _memoController,
        ),
        const SizedBox(height: 20),
        BaraedaButton(
          label: '보고 제출',
          size: BaraedaButtonSize.lg,
          onPressed: _submitting ? null : () => _submit(runId),
        ),
      ],
    );
  }
}
