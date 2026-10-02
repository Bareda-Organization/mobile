// 원본 `design-system/components/core/Badge.jsx` 대응.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 배지 톤. neutral=중립 · brand=브랜드 그린 · amber/red=경고·위험 ·
/// added/removed=diff 표시(초대 명단 변경 등).
enum BaraedaBadgeTone { neutral, brand, amber, red, added, removed }

/// 짧은 라벨·카운트를 보여주는 작은 배지. `BaraedaStatusPill`과 달리
/// 운행 상태 전용이 아니라 범용(신규·변경·카운트 등)이다.
class BaraedaBadge extends StatelessWidget {
  const new({
    required this.label,
    super.key,
    this.tone = BaraedaBadgeTone.neutral,
    this.count,
  });

  final String label;
  final BaraedaBadgeTone tone;

  /// 숫자 카운트. 있으면 라벨 뒤에 `· 3`처럼 붙는다.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone, context.colors);
    final text = count == null ? label : '$label · $count';

    // 자식 Text 와 같은 문구라 자식을 가린다 — 두 번 읽히지 않게(F07-10).
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(BaraedaRadius.sm),
        ),
        child: Text(
          text,
          style: BaraedaTypography.micro.copyWith(
            color: palette.foreground,
            fontWeight: BaraedaFontWeight.medium,
          ),
        ),
      ),
    );
  }
}

class _BadgePalette {
  const new({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_BadgePalette _paletteFor(BaraedaBadgeTone tone, BaraedaColors c) {
  switch (tone) {
    case BaraedaBadgeTone.neutral:
      return _BadgePalette(background: c.bgSubtle, foreground: c.textSecondary);
    case BaraedaBadgeTone.brand:
      return _BadgePalette(
        background: c.accentPrimarySoft,
        foreground: c.textBrand,
      );
    case BaraedaBadgeTone.amber:
      return _BadgePalette(
        background: c.statusMovingSoft,
        foreground: c.statusMoving,
      );
    case BaraedaBadgeTone.red:
      return _BadgePalette(
        background: c.statusMissedSoft,
        foreground: c.statusMissed,
      );
    case BaraedaBadgeTone.added:
      return _BadgePalette(
        background: c.statusBoardedSoft,
        foreground: c.statusBoarded,
      );
    case BaraedaBadgeTone.removed:
      return _BadgePalette(
        background: c.statusMissedSoft,
        foreground: c.statusMissed,
      );
  }
}
