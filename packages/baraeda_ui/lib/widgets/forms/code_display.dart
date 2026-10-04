// 읽기 전용 코드 표시 — 입력 칸(`BaraedaCodeInput`)과 같은 칸 모양으로 이미 만들어진 코드를 보여 준다
// (시안 `link-code*` 의 큰 6칸). 만료된 코드는 글자에 취소선을 긋고 칸을 흐리게 한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 코드 한 줄을 칸마다 한 글자씩 그린다. 낭독기에는 칸이 아니라 코드 전체를 한 글자씩 끊어 읽어 준다.
class BaraedaCodeDisplay extends StatelessWidget {
  const new({required this.code, super.key, this.expired = false});

  final String code;

  /// 만료됐다 — 칸이 흐려지고 글자에 취소선이 그어진다. 색만으로 알리지 않는다.
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spoken = code.split('').join(' ');

    return Semantics(
      label: expired ? '만료된 연결 코드 $spoken' : '연결 코드 $spoken',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, char) in code.characters.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: expired ? colors.disabledSurface : colors.surfaceCard,
                  border: Border.all(color: colors.borderControl),
                  borderRadius: BorderRadius.circular(BaraedaRadius.md),
                ),
                child: Text(
                  char,
                  style: BaraedaTypography.numeric.copyWith(
                    fontSize: 28,
                    color: expired ? colors.disabledText : colors.textPrimary,
                    decoration: expired ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
