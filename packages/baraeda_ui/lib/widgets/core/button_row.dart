// 단추 한 쌍 — 주 단추가 보조보다 넓다(시안 C1: 탑승 · 하차 1.7 : 미승차 1).
// 탑승 · 하차가 거의 전부이고 미승차는 드물어, 이웃 단추를 잘못 누르는 일을 줄인다.

import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:flutter/widgets.dart';

/// 가로로 나란히 놓는 단추들. 첫 단추가 [primaryFlex] 배 넓고 나머지는 같은 폭이다.
/// 단추는 `block: true` 가 아니어도 된다 — 폭은 이 위젯이 정한다.
class BaraedaButtonRow extends StatelessWidget {
  const new({required this.children, super.key, this.primaryFlex = 1.7});

  final List<Widget> children;

  /// 첫(주) 단추의 폭 비율. 나머지는 1.
  final double primaryFlex;

  @override
  Widget build(BuildContext context) {
    // Flexible.flex 는 정수라 소수 비율은 1000 배로 환산한다.
    int flexOf(int i) => i == 0 ? (primaryFlex * 1000).round() : 1000;
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: BaraedaSpacing.space2),
          Expanded(
            flex: flexOf(i),
            child: Align(
              // 단추 높이는 단추 몫 — 가로만 채운다.
              child: SizedBox(width: double.infinity, child: children[i]),
            ),
          ),
        ],
      ],
    );
  }
}
