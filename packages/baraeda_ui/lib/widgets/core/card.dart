// 원본 `design-system/components/core/Card.jsx` 대응.
// readme.md VISUAL FOUNDATIONS: 카드는 흰 배경 + 그린 톤 섀도우이며 보더가
// 없다. 강조는 "왼쪽 컬러 보더"가 아니라 "위쪽 3px 액센트 라인"이다
// (prompt.md: "왼쪽 컬러 보더 패턴은 브랜드에 없습니다").

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:flutter/material.dart';

/// 카드 배경 톤. base=기본 흰 배경 · mist=옅은 브랜드 배경(선택 강조) ·
/// outline=배경 없이 보더만(중첩 카드) · inverse=어두운 배경.
enum BaraedaCardTone { base, mist, outline, inverse }

/// 바래다 기본 카드 컨테이너.
///
/// [accent]를 주면 카드 위쪽에 상태색 3px 라인이 붙는다 — 왼쪽 보더가
/// 아니라 위쪽 라인인 것이 브랜드 규칙이다. `missed`는 한 화면에 카드
/// 하나에만 쓴다(prompt.md).
class BaraedaCard extends StatelessWidget {
  const new({
    required this.child,
    super.key,
    this.tone = BaraedaCardTone.base,
    this.accent,
    this.highlight = false,
    this.padding = const EdgeInsets.all(BaraedaSpacing.cardPadding),
  });

  final Widget child;
  final BaraedaCardTone tone;

  /// 카드 위쪽 3px 상태 액센트 라인. null이면 라인 없음.
  final BaraedaStatus? accent;

  /// 위쪽 3px **초록** 선 — 지금 가장 중요한 카드 하나(시안 `.m-card--hero`).
  /// [accent] 와 함께 주면 [accent] 가 이긴다.
  final bool highlight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = _backgroundFor(tone, colors);
    final border = tone == BaraedaCardTone.outline
        ? Border.all(color: colors.borderDefault)
        : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shadow =
        tone == BaraedaCardTone.outline || tone == BaraedaCardTone.inverse
        ? const <BoxShadow>[]
        : (dark ? BaraedaShadows.cardDark : BaraedaShadows.cardLight);
    final radius = BorderRadius.circular(BaraedaRadius.card);

    final lineColor = accent != null
        ? _accentColorFor(accent!, colors)
        : (highlight ? colors.accentPrimary : null);

    if (lineColor == null) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          border: border,
          borderRadius: radius,
          boxShadow: shadow,
        ),
        child: child,
      );
    }

    // 위쪽 선은 모서리에 맞춰 잘려야 해서 안쪽을 자르고, 그림자는 바깥 상자가 그린다
    // (안에서 그리면 그림자가 같이 잘린다).
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          // 기본(loose)이면 부모가 폭을 정해 줘도 본체가 자식 폭으로 줄어든다
          // (R46-SCREEN — 비상 발신 이력 카드가 화면 폭의 ~30%).
          fit: StackFit.passthrough,
          children: [
            Container(
              padding: padding,
              decoration: BoxDecoration(color: background, border: border),
              child: child,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(height: 3, color: lineColor),
            ),
          ],
        ),
      ),
    );
  }
}

Color _backgroundFor(BaraedaCardTone tone, BaraedaColors c) {
  switch (tone) {
    case BaraedaCardTone.base:
      return c.surfaceCard;
    case BaraedaCardTone.mist:
      return c.accentPrimarySoft;
    case BaraedaCardTone.outline:
      return Colors.transparent;
    case BaraedaCardTone.inverse:
      return c.surfaceInverse;
  }
}

Color _accentColorFor(BaraedaStatus status, BaraedaColors c) {
  switch (status) {
    case BaraedaStatus.boarded:
      return c.statusBoarded;
    case BaraedaStatus.moving:
      return c.statusMoving;
    case BaraedaStatus.missed:
      return c.statusMissed;
    case BaraedaStatus.idle:
      return c.statusIdle;
    case BaraedaStatus.waiting:
      return c.shapeWait;
  }
}
