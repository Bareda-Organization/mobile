import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 번호 매긴 순서 안내 한 줄 — 제목 + 선택 설명.
typedef NumberedStep = ({String title, String? caption});

/// 번호 매긴 순서 안내(시안 `학원에 요청하는 방법` · `자녀 연결 순서`) — 둥근 번호 + 굵은 제목 + 작은 설명.
///
/// 숫자는 낭독기에 따로 읽히지 않는다(순서는 위에서 아래로 읽는 것으로 충분하다).
class NumberedSteps extends StatelessWidget {
  const new({required this.steps, super.key});

  final List<NumberedStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: BaraedaSpacing.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accentPrimary,
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: BaraedaTypography.body.copyWith(
                          color: colors.textInverse,
                          fontWeight: BaraedaFontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WordWrapText(
                      steps[i].title,
                      style: BaraedaTypography.body.copyWith(
                        fontWeight: BaraedaFontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    if (steps[i].caption case final caption?)
                      WordWrapText(
                        caption,
                        style: BaraedaTypography.caption.copyWith(
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
