import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';

/// 카카오내비 길안내 범위 선택(UF-D-02, RUN-08) — `다음 목적지 1개` / `남은 전 구간`.
/// 운전 중 조작을 줄이려고 시트를 거치지 않고 두 버튼을 바로 둔다(누르면 곧바로 그 범위로 연다).
/// 큰 글자에서는 [Wrap] 이 두 번째 버튼을 아래 줄로 내린다.
class NavigationScopeButtons extends StatelessWidget {
  const NavigationScopeButtons({
    required this.onSelected,
    required this.enabled,
    super.key,
  });

  final ValueChanged<NavigationScope> onSelected;

  /// 이미 여는 중이면 `false` — 겹쳐 누르지 않게 한다.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    VoidCallback? press(NavigationScope scope) =>
        enabled ? () => onSelected(scope) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('카카오내비 길안내', style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            BaraedaButton(
              label: '다음 목적지',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: press(NavigationScope.next),
            ),
            BaraedaButton(
              label: '남은 전 구간',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: press(NavigationScope.remaining),
            ),
          ],
        ),
      ],
    );
  }
}
