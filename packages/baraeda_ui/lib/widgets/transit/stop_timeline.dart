// 승하차지 타임라인 — 지난 곳 · 지금 · 이후 · 건너뜀(취소선) · 추가(시안 `.m-stop`).
// 원본: `frontend/design-system/components/transit/StopTimeline.jsx`.
//
// 그리기 방식: `CustomPainter` 대신 위젯 조합(칸 안에 위·아래 연결선 + 번호 원, 옆에 내용 Column)을
// 선택했다 — 승하차지 수가 런타임에 바뀌고 각 행 높이가 텍스트 줄바꿈(주소 유무)에 따라 달라져,
// 캔버스 좌표를 직접 계산하는 것보다 Flutter 레이아웃에 맡기는 편이 유지보수가 쉽다.
//
// 상태는 색만으로 가르지 않는다 — 번호 원의 모양(체크 · 두꺼운 고리 · 빨간 고리 · 초록 고리),
// 글자(취소선), 낭독 문구(`지남` `지금` `건너뜀` `추가`)가 함께 다르다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/badge.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 승하차지 진행 상태. done=지나감 · current=지금(이동 중) · next=다음 · upcoming=이후 ·
/// skipped=건너뜀(경유 안 함, 취소선) · added=추가된 곳.
enum StopState { done, current, next, upcoming, skipped, added }

/// [StopTimeline] 한 항목.
@immutable
class Stop {
  const new({
    required this.name,
    this.address,
    this.time,
    this.state = StopState.upcoming,
    this.riders,
    this.missed,
    this.tag,
    this.tagTone = BaraedaBadgeTone.neutral,
  });

  final String name;
  final String? address;

  /// 도착 예정 또는 실제 시각. 항상 구체적으로("곧" 금지, CONVENTIONS_FLUTTER 카피 규칙).
  final String? time;

  final StopState state;

  /// 이 승하차지 탑승 인원.
  final int? riders;

  /// 미탑승 인원.
  final int? missed;

  /// 이름 옆에 붙는 꼬리표 — `내 승하차지` · `제외` · `추가` 같은 짧은 글자(시안 `.m-stop` 의 칩). 없으면 안 붙는다.
  final String? tag;
  final BaraedaBadgeTone tagTone;
}

/// 노선 승하차지 순서 타임라인 — 세 제품 공통. 번호 원에 순서가 적히고 지금 곳은 앰버로 크다.
class StopTimeline extends StatelessWidget {
  const new({
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
      itemBuilder: (context, index) => _StopTimelineRow(
        stop: stops[index],
        number: index + 1,
        isFirst: index == 0,
        isLast: index == stops.length - 1,
        dense: dense,
        onTap: onSelect == null ? null : () => onSelect!(stops[index], index),
      ),
    );
  }
}

class _StopTimelineRow extends StatelessWidget {
  const new({
    required this.stop,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.dense,
    required this.onTap,
  });

  final Stop stop;
  final int number;
  final bool isFirst;
  final bool isLast;
  final bool dense;
  final VoidCallback? onTap;

  static const double _nodeColumn = 32;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final skipped = stop.state == StopState.skipped;
    final current = stop.state == StopState.current;
    final titleColor = skipped ? colors.statusMissed : colors.textPrimary;

    // 진행 상태는 번호 원의 모양으로만 드러나므로 낭독 문구에 말로 싣고,
    // 자식 Text 는 가려 같은 문구가 두 번 읽히지 않게 한다(F07-10).
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: [
        '$number번',
        stop.name,
        stop.address,
        stop.time,
        switch (stop.state) {
          StopState.done => '지남',
          StopState.current => '지금',
          StopState.next => '다음',
          StopState.upcoming => '이후',
          StopState.skipped => '건너뜀',
          StopState.added => '추가',
        },
        if (stop.riders != null) '${stop.riders}명',
        if (stop.missed != null) '미탑승 ${stop.missed}',
      ].whereType<String>().join(' · '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: BaraedaSpacing.rowMinHeight,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _nodeColumn,
                  child: Column(
                    children: [
                      Expanded(
                        child: isFirst
                            ? const SizedBox.shrink()
                            : _Line(color: colors.borderDefault),
                      ),
                      _Node(number: number, state: stop.state, colors: colors),
                      Expanded(
                        child: isLast
                            ? const SizedBox.shrink()
                            : _Line(color: colors.borderDefault),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: dense ? 6 : 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 승하차지 이름은 두 줄까지 보이고 그 뒤는 `…`. 꼬리표는 이름 옆에 붙는다.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                stop.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: BaraedaTypography.body.copyWith(
                                  height: 1.3,
                                  fontWeight: current
                                      ? BaraedaFontWeight.bold
                                      : BaraedaFontWeight.medium,
                                  color: titleColor,
                                  decoration: skipped
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: titleColor,
                                ),
                              ),
                            ),
                            if (stop.tag != null) ...[
                              const SizedBox(width: BaraedaSpacing.space2),
                              BaraedaBadge(label: stop.tag!, tone: stop.tagTone),
                            ],
                          ],
                        ),
                        if (stop.address != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: WordWrapText(
                              stop.address!,
                              style: BaraedaTypography.micro.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        if (stop.riders != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
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
                if (stop.time != null) ...[
                  const SizedBox(width: BaraedaSpacing.space2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      stop.time!,
                      style: BaraedaTypography.caption.copyWith(
                        height: 1.2,
                        fontWeight: BaraedaFontWeight.medium,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 위·아래 연결선 — 번호 원 가운데를 지나는 2px 선.
class _Line extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    // 높이를 비우면 Center 가 느슨한 제약을 줘서 선이 0 높이로 줄어든다(2026-10-04 시뮬레이터 확인).
    child: SizedBox(
      width: 2,
      height: double.infinity,
      child: ColoredBox(color: color),
    ),
  );
}

/// 번호 원 — 지난 곳은 초록 면 + 체크, 지금은 앰버 면 + 두꺼운 고리(32), 이후는 흰 면 + 고리,
/// 건너뜀은 빨간 고리 · 추가는 초록 고리.
class _Node extends StatelessWidget {
  const new({required this.number, required this.state, required this.colors});

  final int number;
  final StopState state;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    final current = state == StopState.current;
    final done = state == StopState.done;
    final size = current ? 32.0 : 28.0;

    final (fill, ring, ringWidth, textColor) = switch (state) {
      StopState.done => (colors.accentPrimary, null, 0.0, colors.textInverse),
      StopState.current => (colors.mapBus, colors.onNow, 3.0, colors.onNow),
      StopState.next || StopState.upcoming => (
        colors.surfaceCard,
        colors.textPrimary,
        2.5,
        colors.textPrimary,
      ),
      StopState.skipped => (
        colors.surfaceCard,
        colors.dangerSolid,
        2.5,
        colors.statusMissed,
      ),
      StopState.added => (
        colors.surfaceCard,
        colors.shapeBoarded,
        2.5,
        colors.statusBoarded,
      ),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring, width: ringWidth),
      ),
      child: done
          ? BaraedaIcon('check', size: 16, color: textColor)
          : Text(
              '$number',
              style: BaraedaTypography.micro.copyWith(
                color: textColor,
                fontWeight: BaraedaFontWeight.bold,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}
