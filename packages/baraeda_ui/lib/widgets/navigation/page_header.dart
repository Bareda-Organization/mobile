// 관계자 웹 본문 상단 — 제목은 세리프 30px, 설명은 300/14px.
// 원본: `frontend/design-system/components/navigation/PageHeader.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 관계자 웹 페이지 상단 — 제목·설명·우측 액션·하단 탭 슬롯.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.title,
    this.description,
    this.actions,
    this.tabs,
  });

  final String? title;
  final String? description;

  /// 오른쪽 주요 버튼들.
  final Widget? actions;

  /// 하단 탭 영역(SegmentedControl 또는 커스텀).
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BaraedaSpacing.gutterDesktop,
        26,
        BaraedaSpacing.gutterDesktop,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: BaraedaTypography.h1.copyWith(
                          fontSize: 30,
                          height: 1.25,
                          letterSpacing: -0.6,
                        ),
                      ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          description!,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (actions != null)
                Padding(
                  padding: const EdgeInsets.only(left: BaraedaSpacing.space5),
                  child: actions,
                ),
            ],
          ),
          if (tabs != null)
            Container(
              margin: const EdgeInsets.only(top: BaraedaSpacing.space5),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: tabs,
            ),
        ],
      ),
    );
  }
}
