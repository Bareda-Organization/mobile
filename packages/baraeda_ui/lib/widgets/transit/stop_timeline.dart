// 노선 정류장 순서 — 지난 정류장은 그린 선, 현재는 앰버 버스 마커.
// 원본: `frontend/design-system/components/transit/StopTimeline.jsx`.
//
// 그리기 방식: `CustomPainter` 대신 위젯 조합(Column 안에 마커+연결선 Container,
// 옆에 내용 Column)을 선택했다 — 정류장 수가 런타임에 바뀌고 각 행 높이가
// 텍스트 줄바꿈(주소 유무)에 따라 달라져, 캔버스 좌표를 직접 계산하는 것보다
// Flutter 레이아웃에 맡기는 편이 유지보수가 쉽다. 자세한 근거는 보고서 1항.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 정류장 진행 상태. done=지나감 · current=현재 이동 중 · next=다음 정류장 · upcoming=이후.
enum StopState { done, current, next, upcoming }

/// [StopTimeline] 한 항목.
@immutable
class Stop {
  const Stop({
    required this.name,
    this.address,
    this.time,
    this.state = StopState.upcoming,
    this.riders,
    this.missed,
  });

  final String name;
  final String? address;

  /// 도착 예정 또는 실제 시각. 항상 구체적으로("곧" 금지, CONVENTIONS_FLUTTER 카피 규칙).
  final String? time;

  final StopState state;

  /// 이 정류장 탑승 인원.
  final int? riders;

  /// 미탑승 인원.
  final int? missed;
}

/// 노선 정류장 순서 타임라인 — 세 제품 공통. 현재 정류장에 버스 마커가 붙는다.
class StopTimeline extends StatelessWidget {
  const StopTimeline({
    required this.stops,
    super.key,
    this.onSelect,
    this.dense = false,
  });

  final List<Stop> stops;
  final void Function(Stop stop, int index)? onSelect;

  /// 간격 좁게(관계자 웹 목록).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stops.length,
      itemBuilder: (context, index) {
        final stop = stops[index];
        final isLast = index == stops.length - 1;
        return _StopTimelineRow(
          stop: stop,
          isLast: isLast,
          dense: dense,
          onTap: onSelect == null ? null : () => onSelect!(stop, index),
        );
      },
    );
  }
}

class _StopTimelineRow extends StatelessWidget {
  const _StopTimelineRow({
    required this.stop,
    required this.isLast,
    required this.dense,
    required this.onTap,
  });

  final Stop stop;
  final bool isLast;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isCurrent = stop.state == StopState.current;
    final dotColor = switch (stop.state) {
      StopState.done => colors.statusBoarded,
      StopState.current => colors.statusMoving,
      StopState.next || StopState.upcoming => colors.borderDefault,
    };
    final labelColor = switch (stop.state) {
      StopState.done || StopState.upcoming => colors.textSecondary,
      StopState.current || StopState.next => colors.textPrimary,
    };
    final lineColor = stop.state == StopState.done
        ? colors.statusBoarded
        : colors.borderSubtle;

    // 진행 상태(지남·현재·다음·이후)는 점 색과 크기로만 드러나므로 낭독 문구에 말로 싣고,
    // 자식 Text 는 가려 같은 문구가 두 번 읽히지 않게 한다(F07-10).
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: [
        stop.name,
        stop.address,
        stop.time,
        switch (stop.state) {
          StopState.done => '지남',
          StopState.current => '현재 정류장',
          StopState.next => '다음 정류장',
          StopState.upcoming => '이후 정류장',
        },
        if (stop.riders != null) '${stop.riders}명',
        if (stop.missed != null) '미탑승 ${stop.missed}',
      ].whereType<String>().join(' · '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      width: isCurrent ? 24 : 12,
                      height: isCurrent ? 24 : 12,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent ? colors.statusMoving : dotColor,
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: colors.statusMovingSoft,
                                  spreadRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: isCurrent
                          ? BaraedaIcon(
                              'bus',
                              size: 13,
                              color: colors.textInverse,
                            )
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: EdgeInsets.only(
                            top: 4,
                            bottom: dense ? 18 : 26,
                          ),
                          color: lineColor,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLast ? 0 : (dense ? 12 : 18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            stop.name,
                            style: BaraedaTypography.bodySm.copyWith(
                              height: 1.4,
                              fontWeight: isCurrent
                                  ? BaraedaFontWeight.bold
                                  : BaraedaFontWeight.medium,
                              color: labelColor,
                            ),
                          ),
                          if (stop.time != null) ...[
                            const Spacer(),
                            Text(
                              stop.time!,
                              style: BaraedaTypography.micro.copyWith(
                                height: 1,
                                fontWeight: BaraedaFontWeight.bold,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: isCurrent
                                    ? colors.statusMoving
                                    : colors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (stop.address != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: WordWrapText(
                            stop.address!,
                            style: BaraedaTypography.micro.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      if (stop.riders != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BaraedaIcon(
                                'users-round',
                                size: 13,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${stop.riders}명',
                                style: BaraedaTypography.micro.copyWith(
                                  height: 1,
                                  fontWeight: BaraedaFontWeight.regular,
                                  color: colors.textSecondary,
                                ),
                              ),
                              if (stop.missed != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '· 미탑승 ${stop.missed}',
                                  style: BaraedaTypography.micro.copyWith(
                                    height: 1,
                                    fontWeight: BaraedaFontWeight.bold,
                                    color: colors.statusMissed,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
