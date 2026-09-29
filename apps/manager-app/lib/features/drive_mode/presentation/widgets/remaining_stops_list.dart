import 'package:flutter/material.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// 남은 승하차지 목록(M-08 "클릭 → 명단", R32 M5) — 아직 도착 처리하지 않았고 미경유가 아닌
/// 승하차지를 운행 순서대로 보이고, 눌러 펼치면 그곳에서 타고 내릴 학생 이름이 보인다.
/// **조회 전용**이다 — 승하차 처리는 동승자만 한다(M-12 · C-06), 그래서 이 위젯에는 처리
/// 버튼이 없다.
class RemainingStopsList extends StatelessWidget {
  const RemainingStopsList({required this.roster, super.key});

  final RosterResponse roster;

  @override
  Widget build(BuildContext context) {
    final remaining = [
      for (final stop in roster.stops)
        if (stop.change != StopChange.skipped && stop.arrivedAt == null) stop,
    ];
    if (remaining.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('remaining-stops'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '남은 승하차지 ${remaining.length}곳',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final stop in remaining)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(stop.name),
            subtitle: Text('학생 ${stop.students.length}명'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final student in stop.students)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(student.name),
                ),
            ],
          ),
      ],
    );
  }
}
