import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/domain/models/report_request.dart';
import 'package:manager_app/features/run_end/domain/models/report_result.dart';

/// 현장 상황 보고(§4.13, M-14) — 도로 통제 · 차량 문제 · 기타([guardianAbsent] 가 아닐 때, 시안
/// `report`) 또는
/// 보호자 부재(학생 한 명을 골라 보고, 시안 `guardian-absent`). 하원 회차의 예외 보고 화면에서는 네 번째
/// 항목으로 보호자 부재를 고를 수도 있다(UF-E-04 — 동승자의 [예외 보고] → [보호자 부재 보고]).
///
/// 보고는 학원 관계자에게만 전달된다 — 학부모에게 알려야 하면 동승자가 지연 알림을 보낸다. 접수된 뒤에는 제출
/// 단추를 꺼 같은 보고가 두 번 나가지 않게 한다.
class ReportScreen extends ConsumerStatefulWidget {
  const new({super.key, this.guardianAbsent = false});

  /// 보호자 부재 보고로 바로 연다 — 종류 선택 없이 학생 선택이 필수다(`riderId`).
  final bool guardianAbsent;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

/// 보호자 부재로 보고할 수 있는 학생 한 명 — 이름 · 반과 승하차지 이름.
typedef _ReportTarget = ({String riderId, String name, String meta});

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportType _type = ReportType.roadBlock;
  final _memoController = LimitedTextController();
  String? _selectedRiderId;

  bool _submitting = false;
  String? _errorMessage;
  ReportResult? _result;

  /// 보고가 통신 두절로 기기에 쌓였는가 — 서버에 아직 접수되지 않았다. 같은 보고가 두 번 쌓이지 않게 제출 단추를 끈다.
  bool _queued = false;

  /// 보호자 부재 보고인가 — 바로 연 화면이거나, 예외 보고 화면에서 그 종류를 골랐다.
  bool get _isGuardianAbsent =>
      widget.guardianAbsent || _type == ReportType.guardianAbsent;

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  ReportType get _effectiveType =>
      _isGuardianAbsent ? ReportType.guardianAbsent : _type;

  Future<void> _submit(String runId) async {
    final memo = _memoController.text.trim();
    if (_isGuardianAbsent && _selectedRiderId == null) {
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
      final outcome = await ref
          .read(reportsRepositoryProvider)
          .submitReport(
            runId: runId,
            request: ReportRequest(
              type: _effectiveType,
              memo: memo,
              // 즉시 전송과 오프라인 재생이 같은 키를 쓰도록 제출하는 순간 한 번만 만든다.
              clientKey: IdempotencyKeys.generate(),
              riderId: _isGuardianAbsent ? _selectedRiderId : null,
            ),
          );
      if (!mounted) return;
      switch (outcome) {
        case Sent(:final value):
          setState(() => _result = value);
        case Queued():
          ref.invalidate(pendingRequestsProvider);
          setState(() => _queued = true);
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 보호자 부재로 보고할 수 있는 학생 — 버스에 타고 있고 혼자 귀가할 수 없는 학생(EXC-02). 종료 보류 뒤에 열어도
  /// 같다(`Ruling 866`). 도착 응답의 남은 탑승자(`remaining[]`)에는 혼자 귀가 여부가 없어, 명단을 못 받았으면
  /// 대상을 내놓지 않는다.
  List<_ReportTarget> _targets() {
    final roster = ref.watch(rosterProvider).value;
    if (roster == null) return const [];
    return [
      for (final stop in roster.stops)
        for (final student in stop.students)
          if (student.status == RiderStatus.boarded && !student.canGoAlone)
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
    final targets = _isGuardianAbsent ? _targets() : const <_ReportTarget>[];

    return Scaffold(
      appBar: ManagerHeader(
        title: _isGuardianAbsent ? '보호자 부재 보고' : '현장 상황 보고',
        subtitle: _isGuardianAbsent && roster != null
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
                      if (_queued) ...[
                        const AlertBanner(
                          tone: AlertTone.info,
                          title: '보고를 기기에 저장했어요',
                          body: '통신이 끊겨 아직 학원에 전달되지 못했어요 · 연결되면 자동으로 보내요',
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!widget.guardianAbsent)
                        _ReportTypeSelector(
                          includeGuardianAbsent:
                              roster?.direction == RunDirection.fromAcademy,
                          value: _type,
                          onChanged: _submitting
                              ? null
                              : (type) => setState(() => _type = type),
                        ),
                      if (_isGuardianAbsent)
                        _GuardianPicker(
                          leadingGap: !widget.guardianAbsent,
                          rosterLoaded: roster != null,
                          targets: targets,
                          selectedRiderId: _selectedRiderId,
                          onSelect: _submitting
                              ? null
                              : (riderId) =>
                                    setState(() => _selectedRiderId = riderId),
                        ),
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
                        body: _isGuardianAbsent
                            ? '제출하면 학원 관계자에게 바로 전달되고, 이후는 관계자가 판단해요.'
                            : '보고는 학원 관계자에게 전달돼요. 학부모에게 알려야 하면 '
                                  '동승자가 지연 알림을 보내요.',
                      ),
                    ],
                  ),
                ),
                _ReportSubmitBar(
                  // 접수된 뒤에는 끈다 — 다시 누르면 같은 보고가 한 번 더 관계자에게 통지된다.
                  onSubmit: (_submitting || _result != null || _queued)
                      ? null
                      : () => _submit(runId),
                ),
              ],
            ),
    );
  }
}

/// `어떤 상황이에요?` 라벨과 보고 종류 선택 — 하원 회차에서만 `보호자 부재` 가 더해진다(EXC-02).
class _ReportTypeSelector extends StatelessWidget {
  const new({
    required this.includeGuardianAbsent,
    required this.value,
    required this.onChanged,
  });

  final bool includeGuardianAbsent;
  final ReportType value;
  final ValueChanged<ReportType>? onChanged;

  static const _typeOptions = [
    BaraedaSegmentedOption('road_block', label: '도로 통제'),
    BaraedaSegmentedOption('vehicle_issue', label: '차량 문제'),
    BaraedaSegmentedOption('etc', label: '기타'),
  ];

  /// 하원 회차에서만 더해지는 종류 — 보호자 부재는 하원 승하차지의 일이다(EXC-02).
  static const _guardianAbsentOption = BaraedaSegmentedOption(
    'guardian_absent',
    label: '보호자 부재',
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('어떤 상황이에요?', style: BaraedaTypography.label),
        const SizedBox(height: 8),
        BaraedaSegmentedControl(
          options: [
            ..._typeOptions,
            if (includeGuardianAbsent) _guardianAbsentOption,
          ],
          value: value.wireValue,
          block: true,
          wrapByWord: true,
          onChanged: onChanged == null
              ? null
              : (wire) => onChanged!(
                  ReportType.values.firstWhere(
                    (type) => type.wireValue == wire,
                  ),
                ),
        ),
      ],
    );
  }
}

/// `어느 학생이에요?` 라벨과 보호자 부재 대상 학생 고르기 — 대상이 없으면 이유를 글로 보인다.
class _GuardianPicker extends StatelessWidget {
  const new({
    required this.leadingGap,
    required this.rosterLoaded,
    required this.targets,
    required this.selectedRiderId,
    required this.onSelect,
  });

  /// 위 종류 선택이 있을 때 그 사이를 띄운다.
  final bool leadingGap;
  final bool rosterLoaded;
  final List<_ReportTarget> targets;
  final String? selectedRiderId;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leadingGap) const SizedBox(height: 16),
        const Text('어느 학생이에요?', style: BaraedaTypography.label),
        const SizedBox(height: 8),
        if (targets.isEmpty)
          WordWrapText(
            !rosterLoaded
                ? '명단을 불러온 뒤에 학생을 고를 수 있어요.'
                : '보호자 부재로 보고할 학생이 없어요. 혼자 귀가할 수 없는 학생이 '
                      '탑승 중일 때만 고를 수 있어요.',
          )
        else
          BaraedaListGroup(
            children: [
              for (final target in targets)
                BaraedaListRow(
                  title: target.name,
                  titleIsPersonName: true,
                  subtitle: target.meta.isEmpty ? null : target.meta,
                  trailing: BaraedaIcon(
                    selectedRiderId == target.riderId
                        ? 'circle-check'
                        : 'check',
                    color: selectedRiderId == target.riderId
                        ? colors.accentPrimary
                        : colors.borderControl,
                  ),
                  onTap: onSelect == null
                      ? null
                      : () => onSelect!(target.riderId),
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
    );
  }
}

/// 맨 아래 고정 줄 — `보고 제출` 단추.
class _ReportSubmitBar extends StatelessWidget {
  const new({required this.onSubmit});

  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
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
            onPressed: onSubmit,
          ),
        ),
      ),
    );
  }
}
