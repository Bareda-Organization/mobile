import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/live_map_view.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/word_span.dart';

/// 운행 전 화면(시안 `live-map--before`) — 좌표가 없는데 지도를 그릴 근거가 없으므로 지도 대신
/// 출발 시각 안내 + 그 회차 카드 + [노선 미리 보기].
///
/// 회차 목록을 못 받았으면(`404 RUN_NOT_FOUND` 포함) 출발 시각을 모르므로 카드 없이 안내 한 줄만 둔다.
class LiveMapBefore extends StatelessWidget {
  const new({
    required this.studentId,
    required this.view,
    required this.studentName,
    required this.switcher,
    super.key,
  });

  final String studentId;
  final LiveMapView view;

  /// 학부모는 선택한 자녀 이름, 학생 본인은 `null`.
  final String? studentName;

  /// 자녀가 둘 이상일 때만 있다.
  final Widget? switcher;

  @override
  Widget build(BuildContext context) {
    final run = view.run;

    return Scaffold(
      appBar: const AppHeader(title: '실시간 버스'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          children: [
            ?switcher,
            if (run == null)
              const EmptyState(
                title: '아직 위치 정보가 없습니다',
                body: '버스가 운행을 시작하면 실시간 위치가 표시됩니다',
              )
            else ...[
              _Hero(run: run),
              const SizedBox(height: BaraedaSpacing.space4),
              _RunCard(run: run, studentName: studentName, busNo: view.busNo),
              const SizedBox(height: BaraedaSpacing.space3),
              BaraedaButton(
                label: '노선 미리 보기',
                variant: BaraedaButtonVariant.secondary,
                block: true,
                onPressed: () => context.push(
                  AppRoutes.routeDetailFor(
                    studentId: studentId,
                    runId: view.runId,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 시계 그림 + "버스가 아직 출발 전이에요" + 출발 시각 안내.
class _Hero extends StatelessWidget {
  const new({required this.run});

  final StudentRun run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = BaraedaTypography.body.copyWith(
      color: colors.textSecondary,
      height: 1.6,
    );

    return Padding(
      padding: const EdgeInsets.only(top: BaraedaSpacing.space10),
      child: Column(
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.statusIdleSoft,
              ),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: BaraedaIcon(
                    'clock',
                    size: 28,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: BaraedaSpacing.space4),
          const Text(
            '버스가 아직 출발 전이에요',
            textAlign: TextAlign.center,
            style: BaraedaTypography.h3,
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          Text.rich(
            TextSpan(
              children: [
                wordSpan('${run.direction.label} 버스는 ', style: bodyStyle),
                wordSpan(
                  formatClock(run.departTime),
                  style: bodyStyle.copyWith(
                    color: colors.textPrimary,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
                wordSpan('에 출발해요.', style: bodyStyle),
                const TextSpan(text: '\n'),
                wordSpan('출발하면 이 화면에서 위치를 볼 수 있어요.', style: bodyStyle),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 그 회차 카드 — "하준이 하원 · 14:40 출발" + 확정 여부 칩 + 승하차지 · 호차 · 확정 시각.
class _RunCard extends StatelessWidget {
  const new({
    required this.run,
    required this.studentName,
    required this.busNo,
  });

  final StudentRun run;
  final String? studentName;
  final String? busNo;

  @override
  Widget build(BuildContext context) {
    final name = studentName;
    final who = name == null
        ? '내 ${run.direction.label}'
        : '$name ${run.direction.label}';
    // 확정(출발 30분 전)은 사용자 조작이 아니라 시각이 정한다 — 아직이면 그 시각을 알려 준다(C-04).
    final confirmAt = run.departTime.subtract(const Duration(minutes: 30));
    final hint = [
      run.stop.name,
      busNo ?? run.busNo,
      if (!run.confirmed) '${formatClock(confirmAt)} 에 노선이 확정돼요',
    ].join(' · ');

    return BaraedaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: WordWrapText(
                  '$who · ${formatClock(run.departTime)} 출발',
                  style: BaraedaTypography.body.copyWith(
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space2),
              BaraedaStatusPill(
                status: run.confirmed
                    ? BaraedaStatus.boarded
                    : BaraedaStatus.waiting,
                label: run.confirmed ? '확정' : '확정 전',
              ),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space1),
          WordWrapText(
            hint,
            style: BaraedaTypography.caption.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
