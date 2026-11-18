import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';

/// 구간 안내 띠 — ①바로 반영 / ②승인이 필요해요(회차당 1번).
class ChangeZoneNotice extends ConsumerWidget {
  const new({required this.run, super.key});

  final StudentRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmAt = formatClock(run.departTime.subtract(confirmLead));
    return switch (changeZoneOf(run, ref.read(clockProvider).now())) {
      ChangeZone.immediate => AlertBanner(
        tone: AlertTone.info,
        title: '바로 반영돼요',
        body: '$confirmAt 이후에는 학원 승인이 필요해요',
      ),
      ChangeZone.approval => const AlertBanner(
        tone: AlertTone.moving,
        title: '학원 승인이 필요해요',
        body: '이 회차에서 1번만 신청할 수 있어요. 운행이 시작되기 전까지 승인되지 않으면 자동 반려돼요.',
      ),
      // 일일 변경에서 고를 수 없는 회차(꺼진 칸)라 보통 닿지 않는다 — 고른 뒤 시각이 넘어간 경우만.
      ChangeZone.closed => const AlertBanner(
        tone: AlertTone.missed,
        title: '변경 신청 마감이 지났어요',
        body: '탑승 취소는 홈에서 할 수 있어요.',
      ),
    };
  }
}
