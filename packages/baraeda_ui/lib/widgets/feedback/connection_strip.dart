// 연결 끊김 · 오프라인 띠 — 화면 맨 위에 붙는 한 줄(시안 `.m-strip`).
// 끊김은 어두운 면, 다시 연결하는 중은 앰버, 복구는 초록이다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 연결 띠의 상태.
enum BaraedaConnectionState {
  /// 연결이 끊겼다 — 어두운 잉크 면(다크 구역에서는 밝은 면).
  offline,

  /// 다시 연결하는 중 — 앰버.
  reconnecting,

  /// 다시 연결됐다 — 초록.
  restored,
}

/// 연결 상태 한 줄 띠. 높이 40 이상 · 글자 14. 낭독은 문구를 알림 영역(liveRegion)으로 읽는다.
class BaraedaConnectionStrip extends StatelessWidget {
  const new({
    required this.state,
    required this.message,
    super.key,
    this.trailing,
  });

  final BaraedaConnectionState state;

  /// 예: `연결이 끊겼어요 · 처리 대기 2건`.
  final String message;

  /// 오른쪽에 둘 한 가지 행동(예: 다시 연결).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground, icon, line) = switch (state) {
      BaraedaConnectionState.offline => (
        colors.inkSurface,
        colors.onInkSurface,
        'wifi-off',
        null,
      ),
      BaraedaConnectionState.reconnecting => (
        colors.statusMovingSoft,
        colors.statusMoving,
        'refresh',
        colors.shapeMoving,
      ),
      BaraedaConnectionState.restored => (
        colors.statusBoardedSoft,
        colors.statusBoarded,
        'check',
        null,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: line == null ? null : Border(bottom: BorderSide(color: line)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.gutterMobile,
              vertical: 6,
            ),
            child: Row(
              children: [
                ExcludeSemantics(child: BaraedaIcon(icon, color: foreground)),
                const SizedBox(width: BaraedaSpacing.space2),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BaraedaTypography.caption.copyWith(
                        color: foreground,
                        fontWeight: BaraedaFontWeight.medium,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
