import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/roster/domain/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_actions.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/no_show_body.dart';
import 'package:manager_app/features/roster/presentation/widgets/no_show_contact_sheet.dart';

/// 미승차 연락(M-13 · M-14, 시안 `no-show`) — 미승차로 처리한 학생 한 명의 연락 대기 시간(기본 3분)을 세고,
/// 보호자에게 전화하고, 연락 기록을 남긴다. 명단의 `연락` 단추가 여기로 온다.
///
/// 연락 이력은 서버가 준 `no_show_case.contacts[]` 를 그대로 그린다(`Ruling 823`) — **시각 · 수단
/// · 결과뿐**이다.
/// 메모를 받지 않으므로 "보호자 이름 문의" 같은 줄은 만들지 않는다. 대기 시간은 서버가 정한
/// `expires_at` 이라 앱에 상수를 두지 않는다.
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

  /// 방금 남긴 연락 기록이 통신 두절로 기기에 쌓였는가 — 서버에 아직 반영되지 않았다.
  bool _queued = false;

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
      _queued = false;
    });
    final result = await submitNoShowContact(
      container,
      runId: runId,
      riderId: riderId,
      request: request,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      _queued = result.queued;
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
          : NoShowBody(
              stop: found.stop,
              student: found.student,
              busy: _busy,
              error: _error,
              queued: _queued,
              onCall: () => unawaited(_call(runId, found.student.riderId)),
              onRecord: (waitEndsAt) =>
                  unawaited(_record(runId, found.student.riderId, waitEndsAt)),
              onRevert: () => unawaited(_revert(runId, found.student.riderId)),
            ),
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
