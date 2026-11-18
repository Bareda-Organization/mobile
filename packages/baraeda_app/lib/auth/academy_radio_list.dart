import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 검색 결과 라디오 목록 — 한 카드 안에 줄마다 `학원명` + `지역 · 학원 코드`.
class AcademyRadioList extends StatelessWidget {
  const new({
    required this.academies,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<AcademySummary> academies;
  final String? selectedId;
  final ValueChanged<AcademySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const radius = BorderRadius.all(Radius.circular(BaraedaRadius.card));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: radius,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          children: [
            for (var i = 0; i < academies.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: _AcademyRow(
                  academy: academies[i],
                  selected: academies[i].id == selectedId,
                  onTap: () => onSelected(academies[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AcademyRow extends StatelessWidget {
  const new({
    required this.academy,
    required this.selected,
    required this.onTap,
  });

  final AcademySummary academy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = '${academy.region} · 학원 코드 ${academy.code}';

    return BaraedaPressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      selected: selected,
      semanticLabel: '${academy.name}, $caption',
      child: ColoredBox(
        color: selected ? colors.accentPrimarySoft : colors.surfaceCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space3,
              vertical: BaraedaSpacing.space2,
            ),
            child: Row(
              children: [
                _RadioMark(selected: selected),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WordWrapText(
                        academy.name,
                        style: BaraedaTypography.body.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          height: 1.3,
                        ),
                      ),
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
          ),
        ),
      ),
    );
  }
}

/// 둥근 라디오 표시 — 고른 줄은 가운데에 점이 찬다(색만으로 구분하지 않는다).
class _RadioMark extends StatelessWidget {
  const new({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderControl,
            width: 2,
          ),
        ),
        child: SizedBox(
          width: 24,
          height: 24,
          child: selected
              ? Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentPrimary,
                    ),
                    child: const SizedBox(width: 12, height: 12),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
