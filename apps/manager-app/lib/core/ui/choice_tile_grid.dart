import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// [ChoiceTileGrid] 의 한 칸 — 아이콘 · 이름 · (선택) 보조 줄.
class ChoiceTileOption<T> {
  const new({
    required this.value,
    required this.label,
    required this.icon,
    this.hint,
  });

  final T value;
  final String label;

  /// `BaraedaIcon` 이름.
  final String icon;

  /// 이름 아래 작은 글(예: `메모 필수`).
  final String? hint;
}

/// 2열 카드 격자에서 하나를 고른다(시안 `.mm-tiles` — 지연 사유 · 비상 유형). 고른 칸은 초록 2px 둘레선과
/// 오른쪽 위 체크 표식, 나머지는 1px 둘레선이다. [onChanged] 가 null 이면 모든 칸이 눌리지 않는다.
class ChoiceTileGrid<T> extends StatelessWidget {
  const new({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<ChoiceTileOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    const gap = BaraedaSpacing.space2;
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += 2) {
      final pair = options.skip(i).take(2).toList();
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < 2; j++) ...[
                if (j == 1) const SizedBox(width: gap),
                Expanded(
                  child: j < pair.length
                      ? _Tile<T>(
                          option: pair[j],
                          selected: pair[j].value == value,
                          onTap: onChanged == null
                              ? null
                              : () => onChanged!(pair[j].value),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _Tile<T> extends StatelessWidget {
  const new({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChoiceTileOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(BaraedaRadius.control);
    return BaraedaPressable(
      onTap: onTap,
      borderRadius: radius,
      selected: selected,
      semanticLabel: option.hint == null
          ? option.label
          : '${option.label}, ${option.hint}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: radius,
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderControl,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BaraedaIcon(
                    option.icon,
                    size: 24,
                    color: selected ? colors.accentPrimary : colors.textPrimary,
                  ),
                  const SizedBox(height: BaraedaSpacing.space2),
                  Text(
                    option.label,
                    style: BaraedaTypography.body.copyWith(
                      color: colors.textPrimary,
                      fontWeight: BaraedaFontWeight.bold,
                    ),
                  ),
                  if (option.hint != null)
                    Text(
                      option.hint!,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: BaraedaSpacing.space2,
                right: BaraedaSpacing.space2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accentPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: Center(
                      child: BaraedaIcon(
                        'check',
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
