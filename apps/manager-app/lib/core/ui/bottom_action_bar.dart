import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 화면 맨 아래에 붙는 단추 줄(시안 `.m-footer`) — 위에 1px 선, 홈 표시줄 위 안전 영역을 비킨다.
/// 단추는 세로로 쌓는다.
class BottomActionBar extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgBase,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
