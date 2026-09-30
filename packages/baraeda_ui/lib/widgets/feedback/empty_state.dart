// 비어 있는 목록 — 운행 전 시간대, 알림 없음, 검색 결과 없음.
// 원본: `frontend/design-system/components/feedback/EmptyState.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 목록이 비었을 때 화면 중앙에 두는 안내.
///
/// 예: `EmptyState(icon: 'clock', title: '오늘 운행이 아직 시작되지 않았어요',
/// body: '등원 운행은 8:10에 시작됩니다.')`.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = 'bus',
    this.title,
    this.body,
    this.action,
  });

  /// Lucide 아이콘 이름.
  final String icon;
  final String? title;

  /// 보조 설명. React 쪽 `children`에 대응.
  final String? body;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      // 제목·본문을 자식이 각자 읽는다 — 합친 라벨을 또 얹으면 두 번 읽힌다(F07-10).
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.bgSubtle,
                shape: BoxShape.circle,
              ),
              child: BaraedaIcon(icon, size: 26, color: colors.textBrand),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: BaraedaTypography.h3.copyWith(
                    fontSize: 20,
                    height: 1.4,
                  ),
                ),
              ),
            if (body != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: BaraedaTypography.caption.copyWith(
                    fontWeight: BaraedaFontWeight.light,
                    height: 1.7,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 20), child: action),
          ],
        ),
      ),
    );
  }
}
