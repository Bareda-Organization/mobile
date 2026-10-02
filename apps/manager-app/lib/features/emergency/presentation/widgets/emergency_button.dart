import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';

/// 머리말 비상 버튼(M-15 · UF-X-08, R32 M2) — 기사·동승자 모두, 홈·운행·명단 세 화면 머리말에
/// 둔다. 눌러서 비상 신고 화면(`AppRoutes.emergency`)으로 간다.
///
/// 운행 화면·명단 화면은 이미 회차가 골라져 있어 바로 간다. 홈은 회차를 아직 고르지 않았으므로
/// [homeRuns](오늘 배정된 회차 전부)를 받아 신고할 수 있는 회차를 찾는다 — 확정 이후이고
/// 아직 끝나지 않은 회차([canRaiseEmergency]). 운행 중이 아니어도 된다(출발 전 차량 이상).
class EmergencyButton extends ConsumerWidget {
  const new({super.key, this.homeRuns});

  /// 홈에서만 넘긴다. `null` 이면 이미 골라진 회차([selectedRunIdProvider])로 간다.
  final List<ManagerRun>? homeRuns;

  /// 비상을 보낼 수 있는 회차 — 확정 이후(`confirmed` · `moving`)이고 종료 전이다.
  static bool canRaiseEmergency(ManagerRun run) =>
      run.confirmed &&
      (run.runStatus == RunStatus.confirmed ||
          run.runStatus == RunStatus.moving);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: () => unawaited(_open(context, ref)),
      child: const Text('비상'),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final shown = homeRuns;
    if (shown == null) {
      await context.push(AppRoutes.emergency);
      return;
    }
    // 홈 목록은 한 번 받은 뒤 낡을 수 있다(확정 시각이 지났는데 "확정된 운행이 없다" 로 막힌다, F06-13) —
    // 판정 직전에 다시 받는다. 못 받으면 가진 목록으로 판정한다(통신 두절에서도 신고 길이 막히지 않게).
    List<ManagerRun> runs;
    try {
      runs = await ref.refresh(todayRunsProvider.future);
    } on Object {
      runs = shown;
    }
    if (!context.mounted) return;
    final candidates = runs.where(canRaiseEmergency).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: WordWrapText('확정된 운행이 있을 때 비상 신고를 보낼 수 있습니다')),
      );
      return;
    }
    final run = candidates.length == 1
        ? candidates.single
        : await _choose(context, candidates);
    if (run == null || !context.mounted) return;
    ref.read(selectedRunIdProvider.notifier).state = run.runId;
    await context.push(AppRoutes.emergency);
  }

  /// 신고할 수 있는 회차가 여럿일 때 고르게 한다 — 엉뚱한 회차로 신고가 나가면 관계자가 다른
  /// 버스로 출동한다.
  Future<ManagerRun?> _choose(BuildContext context, List<ManagerRun> runs) {
    return showDialog<ManagerRun>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('어느 운행의 비상입니까?'),
        children: [
          for (final run in runs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(run),
              child: Text(
                '${run.busNo} · '
                '${run.direction == RunDirection.toAcademy ? '등원' : '하원'} · '
                '${DateFormat('HH:mm').format(run.departTime.toLocal())}'
                '${run.runStatus == RunStatus.moving ? ' · 운행 중' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}
