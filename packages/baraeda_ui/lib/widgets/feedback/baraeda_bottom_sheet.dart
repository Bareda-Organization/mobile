// 지도 위에서 정보를 겹쳐 보여줄 때 — 실시간 위치 화면의 운행 요약, 정류장 상세.
// 원본: `frontend/design-system/components/feedback/BottomSheet.jsx`.
//
// Flutter `showModalBottomSheet`/`material.BottomSheet` 와 이름이 겹쳐
// `Baraeda` 접두를 붙인다(팀 리드 지시).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 지도 위에 겹쳐 뜨는 바텀시트.
///
/// 반드시 [Stack] 의 직계 자식으로 두어야 한다 — 내부에서 [Positioned.fill] 로
/// 스스로를 부모 크기만큼 펼친다. 상단만 둥근 모서리이며, 세 제품 중
/// 유일하게 `--shadow-sheet`(위로 뻗는 그림자)를 쓴다.
class BaraedaBottomSheet extends StatelessWidget {
  const BaraedaBottomSheet({super.key, this.title, this.child, this.onClose});

  final String? title;
  final Widget? child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: Container(color: colors.overlayScrim),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Semantics(
              namesRoute: true,
              label: title,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  BaraedaSpacing.space5,
                  BaraedaSpacing.space3,
                  BaraedaSpacing.space5,
                  BaraedaSpacing.space6,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceCard,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(BaraedaRadius.sheet),
                    topRight: Radius.circular(BaraedaRadius.sheet),
                  ),
                  boxShadow: BaraedaShadows.sheet,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(
                          bottom: BaraedaSpacing.space3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.borderDefault,
                          borderRadius: BorderRadius.circular(
                            BaraedaRadius.pill,
                          ),
                        ),
                      ),
                    ),
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: BaraedaSpacing.space3,
                        ),
                        child: Text(
                          title!,
                          style: BaraedaTypography.h3.copyWith(
                            fontSize: 20,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (child != null) child!,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
