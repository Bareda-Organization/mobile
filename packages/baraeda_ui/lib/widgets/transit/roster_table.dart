// 관계자 웹 전용 표 — 헤더는 미스트 배경, 행 구분은 1px 선만.
// 원본: `frontend/design-system/components/transit/RosterTable.jsx`.
//
// 모바일 폭 처리: 관계자 웹 전용(모바일 화면에는 쓰이지 않음)이지만 디자인
// 시스템 구성요소로는 만들어야 한다. 좁은 화면에서 열을 찌그러뜨리는 대신
// 표 전체를 `SingleChildScrollView(Axis.horizontal)` 로 감싸 가로 스크롤시킨다
// — 웹 데이터 표의 통상적인 반응형 패턴이며, 열 폭([RosterColumn.width])을
// 그대로 지켜 내용이 잘리거나 줄바꿈되지 않게 한다. 자세한 근거는 보고서 1항.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 열 정렬.
enum RosterColumnAlign { left, center, right }

/// [RosterTable] 한 열의 정의.
@immutable
class RosterColumn<T> {
  const RosterColumn({
    required this.key,
    required this.label,
    required this.cellBuilder,
    this.align = RosterColumnAlign.left,
    this.width = 140,
  });

  final String key;
  final String label;
  final RosterColumnAlign align;

  /// 열 폭. React 원본은 `width` 미지정 열을 남는 공간에 맡기지만, Flutter 는
  /// 가로 스크롤 표에서 명시적 폭이 필요해 기본값 140을 둔다.
  final double width;

  /// 셀 내용. React 쪽 `render(row)` 에 대응.
  final Widget Function(BuildContext context, T row) cellBuilder;

  Alignment get _cellAlignment => switch (align) {
    RosterColumnAlign.left => Alignment.centerLeft,
    RosterColumnAlign.center => Alignment.center,
    RosterColumnAlign.right => Alignment.centerRight,
  };

  TextAlign get _textAlign => switch (align) {
    RosterColumnAlign.left => TextAlign.left,
    RosterColumnAlign.center => TextAlign.center,
    RosterColumnAlign.right => TextAlign.right,
  };
}

/// 관계자 웹 명단 표 — 버스별 탑승 인원, 학생 명부, 매니저 목록.
class RosterTable<T> extends StatelessWidget {
  const RosterTable({
    required this.columns,
    required this.rows,
    super.key,
    this.onRowTap,
    this.rowKey,
  });

  final List<RosterColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;

  /// 행 식별자. 없으면 인덱스를 쓴다(React 쪽 `r.id || i`에 대응).
  final Object? Function(T row)? rowKey;

  double get _tableWidth => columns.fold<double>(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? BaraedaShadows.cardDark
        : BaraedaShadows.cardLight;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        boxShadow: shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _tableWidth,
          child: Column(
            children: [
              _RosterHeaderRow(columns: columns),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _RosterBodyRow<T>(
                    columns: columns,
                    row: row,
                    onTap: onRowTap == null ? null : () => onRowTap!(row),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterHeaderRow<T> extends StatelessWidget {
  const _RosterHeaderRow({required this.columns});

  final List<RosterColumn<T>> columns;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.bgSubtle,
      child: Row(
        children: [
          for (final column in columns)
            SizedBox(
              width: column.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BaraedaSpacing.space4,
                  vertical: BaraedaSpacing.space3,
                ),
                child: Align(
                  alignment: column._cellAlignment,
                  child: Text(
                    column.label,
                    textAlign: column._textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.micro.copyWith(
                      height: 1,
                      fontWeight: BaraedaFontWeight.medium,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RosterBodyRow<T> extends StatelessWidget {
  const _RosterBodyRow({
    required this.columns,
    required this.row,
    required this.onTap,
  });

  final List<RosterColumn<T>> columns;
  final T row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.borderSubtle)),
        ),
        child: Row(
          children: [
            for (final column in columns)
              SizedBox(
                width: column.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaraedaSpacing.space4,
                    vertical: 13,
                  ),
                  child: Align(
                    alignment: column._cellAlignment,
                    child: column.cellBuilder(context, row),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
