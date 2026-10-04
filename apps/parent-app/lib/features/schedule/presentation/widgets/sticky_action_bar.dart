import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 화면 맨 아래 고정 단추 자리 — 엄지가 닿는 곳에 주 행동(시안 `.m-sticky`). 위에 가는 선을 긋는다.
class StickyActionBar extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceChrome,
        border: Border(top: BorderSide(color: colors.borderChrome)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: child,
        ),
      ),
    );
  }
}
