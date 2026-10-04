import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_actions.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/no_show_contact_sheet.dart';

/// 미승차 연락(M-13 · M-14, 시안 `no-show`) — 미승차로 처리한 학생 한 명의 연락 대기 시간(기본 3분)을 세고,
/// 보호자에게 전화하고, 연락 기록을 남긴다. 명단의 `연락` 단추가 여기로 온다.
///
/// 연락 이력은 서버가 준 `no_show_case.contacts[]` 를 그대로 그린다(`Ruling 823`) — **시각 · 수단
/// · 결과뿐**이다.
/// 메모를 받지 않으므로 "보호자 이름 문의" 같은 줄은 만들지 않는다. 대기 시간은 서버가 정한
/// `expires_at` 이라 앱에 상수를 두지 않는다(R32 M12).
class NoShowScreen extends ConsumerStatefulWidget {
  const new({required this.riderId, super.key});

  final String? riderId;

  @override
  ConsumerState<NoShowScreen> createState() => _NoShowScreenState();
}

class _NoShowScreenState extends ConsumerState<NoShowScreen> {
  Timer? _ticker;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _call(String runId, String riderId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await callGuardian(ref, runId: runId, riderId: riderId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _record(
    String runId,
    String riderId,
    DateTime? waitEndsAt,
  ) async {
    final clock = ref.read(clockProvider);
    final request = await showBaraedaBottomSheet<NoShowContactRequest>(
      context: context,
      title: '연락 기록',
      showCloseButton: true,
      builder: (context) =>
          NoShowContactSheet(waitEndsAt: waitEndsAt, clock: clock),
    );
    if (request == null || !mounted) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await submitNoShowContact(
      container,
      runId: runId,
      riderId: riderId,
      request: request,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _revert(String runId, String riderId) async {
    final confirmed = await showBaraedaConfirmDialog(
      context: context,
      title: '미승차를 되돌릴까요?',
      body: '대기 상태로 돌아가고 연락 대기가 멈춰요.',
      confirmLabel: '되돌리기',
      cancelLabel: '닫기',
    );
    if (!confirmed || !mounted) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .revertRiderStatus(runId: runId, riderId: riderId);
      container.invalidate(rosterProvider);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final roster = ref.watch(rosterProvider).value;
    final found = roster == null ? null : _find(roster, widget.riderId);

    return Scaffold(
      appBar: ManagerHeader(
        title: '미승차 연락',
        subtitle: found == null || roster == null
            ? null
            : '${roster.busNo} · ${directionLabel(roster.direction)} · '
                  '${found.stop.name}',
      ),
      body: runId == null || found == null || found.student.noShowCase == null
          ? const EmptyState(
              icon: 'check',
              title: '연락할 미승차가 없어요',
              body: '미승차가 되돌려졌거나 이미 끝났어요. 명단에서 다시 확인해 주세요.',
            )
          : _buildBody(context, runId, found.stop, found.student),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String runId,
    RosterStop stop,
    RosterStudent student,
  ) {
    final colors = context.colors;
    final noShow = student.noShowCase!;
    final now = ref.watch(clockProvider).now();
    final total = noShow.expiresAt.difference(noShow.startedAt);
    final left = noShow.expiresAt.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;
    final progress = total.inSeconds <= 0
        ? 1.0
        : (1 - remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    final contacts = noShow.contacts;
    final lastResult = contacts.isEmpty ? null : contacts.last.result;
    String two(int n) => n.toString().padLeft(2, '0');
    final clockText =
        '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}';
    final waitMinutes = (total.inSeconds / 60).round();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              BaraedaCard(
                highlight: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _Initial(name: student.name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name,
                                style: BaraedaTypography.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                [
                                  student.className,
                                  stop.name,
                                ].whereType<String>().join(' · '),
                                style: BaraedaTypography.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const BaraedaStatusPill(
                          status: BaraedaStatus.missed,
                          label: '미승차',
                          size: BaraedaStatusPillSize.lg,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          clockText,
                          style: BaraedaTypography.display.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            remaining == Duration.zero
                                ? '연락 대기가 끝났어요'
                                : '연락 대기 남음',
                            style: BaraedaTypography.body.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BaraedaRadius.pill),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: colors.accentPrimary,
                        backgroundColor: colors.statusIdleSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_hms(noShow.startedAt)} 미승차 처리 · '
                      '${hhmm(noShow.expiresAt)} 에 끝나요',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BaraedaCard(
                child: StopTimeline(
                  stops: [
                    Stop(
                      name: '학부모·관계자에게 알려줬어요',
                      address: _hms(noShow.startedAt),
                      state: StopState.done,
                    ),
                    Stop(
                      name: '보호자에게 전화',
                      address: contacts.isEmpty
                          ? '아직 시도하지 않았어요'
                          : '${contacts.length}회 시도 · '
                                '${_resultLabel(lastResult!)}',
                      state: StopState.current,
                    ),
                    Stop(
                      name: '$waitMinutes분이 지나면 관계자에게 보고돼요',
                      address: '출발 · 재시도는 관계자 판단이에요',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '연락 기록',
                      style: BaraedaTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${contacts.length}건',
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '아직 남긴 연락 기록이 없어요',
                    style: BaraedaTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                BaraedaListGroup(
                  children: [
                    // 서버가 시각순으로 준다 — 화면은 그대로 위에서 아래로 그린다.
                    for (final contact in contacts)
                      BaraedaListRow(
                        key: ValueKey(
                          'contact-${contact.attemptedAt.toIso8601String()}',
                        ),
                        leadingIcon:
                            contact.attemptType == NoShowAttemptType.call
                            ? 'phone'
                            : 'bell',
                        title:
                            '${_typeLabel(contact.attemptType)} · '
                            '${_resultLabel(contact.result)}',
                        subtitle: _hms(contact.attemptedAt),
                      ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AlertBanner(tone: AlertTone.missed, body: _error),
              ],
              const SizedBox(height: 8),
              Center(
                child: BaraedaButton(
                  label: '미승차 되돌리기',
                  icon: 'undo',
                  variant: BaraedaButtonVariant.ghost,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_revert(runId, student.riderId)),
                ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BaraedaButton(
                    label: '보호자에게 전화',
                    icon: 'phone',
                    size: BaraedaButtonSize.xl,
                    block: true,
                    onPressed: _busy || student.guardianPhone == null
                        ? null
                        : () => unawaited(_call(runId, student.riderId)),
                    disabledReason: student.guardianPhone == null
                        ? '연결된 보호자가 없어요'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  BaraedaButton(
                    label: '연락 기록 남기기',
                    variant: BaraedaButtonVariant.secondary,
                    block: true,
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _record(runId, student.riderId, noShow.expiresAt),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  ({RosterStop stop, RosterStudent student})? _find(
    RosterResponse roster,
    String? riderId,
  ) {
    for (final stop in roster.stops) {
      for (final student in stop.students) {
        if (student.riderId == riderId) return (stop: stop, student: student);
      }
    }
    return null;
  }
}

String _hms(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _typeLabel(NoShowAttemptType type) =>
    type == NoShowAttemptType.call ? '전화' : '문자';

String _resultLabel(NoShowContactResult result) =>
    result == NoShowContactResult.answered ? '응답함' : '무응답';

/// 학생 이름 끝 두 글자 — 사진 없는 아바타(명단 행과 같은 규칙).
class _Initial extends StatelessWidget {
  const new({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initials = name.length >= 2 ? name.substring(name.length - 2) : name;
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.statusIdleSoft,
        borderRadius: BorderRadius.circular(BaraedaRadius.control),
      ),
      child: ExcludeSemantics(
        child: Text(
          initials,
          style: BaraedaTypography.title.copyWith(color: colors.textBrand),
        ),
      ),
    );
  }
}
