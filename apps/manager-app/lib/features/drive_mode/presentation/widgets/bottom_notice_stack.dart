import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 운행 화면 하단 고정 영역에 띄울 알림 한 건.
class BottomNotice {
  const BottomNotice({required this.tone, required this.body, this.action});

  final AlertTone tone;
  final String body;

  /// 알림 아래에 붙는 다음 행동(예: `[설정 열기]`).
  final Widget? action;
}

/// 하단 고정 영역의 알림 묶음(Ruling 571·572) — **가장 중요한 한 건만** 보이고 나머지는 `알림 N건 더 보기` 로 접는다.
/// 알림이 쌓이면 고정 영역이 커져 위쪽 지도가 밀려나고 큰 글자에서는 [도착 처리] 가 화면 밖으로 나간다(R46).
/// 그래서 묶음 전체의 높이를 화면 높이의 [maxHeightFraction] 로 막고, 넘치면 안에서 스크롤한다.
class BottomNoticeStack extends StatefulWidget {
  const BottomNoticeStack({required this.notices, super.key});

  /// 화면 높이에서 묶음이 차지할 수 있는 최대 비율. 작은 화면(360×640)에서 256px.
  static const maxHeightFraction = 0.4;

  /// 중요한 순서 — 첫 번째가 접힌 상태에서 보이는 알림이다.
  final List<BottomNotice> notices;

  @override
  State<BottomNoticeStack> createState() => _BottomNoticeStackState();
}

class _BottomNoticeStackState extends State<BottomNoticeStack> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notices = widget.notices;
    if (notices.isEmpty) return const SizedBox.shrink();
    final hiddenCount = notices.length - 1;
    final shown = _expanded ? notices : notices.take(1);
    final maxHeight =
        MediaQuery.sizeOf(context).height * BottomNoticeStack.maxHeightFraction;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                spacing: 8,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final notice in shown)
                    AlertBanner(
                      tone: notice.tone,
                      body: notice.body,
                      action: notice.action,
                    ),
                ],
              ),
            ),
          ),
          if (hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: BaraedaButton(
                label: _expanded ? '알림 접기' : '알림 $hiddenCount건 더 보기',
                size: BaraedaButtonSize.sm,
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
        ],
      ),
    );
  }
}
