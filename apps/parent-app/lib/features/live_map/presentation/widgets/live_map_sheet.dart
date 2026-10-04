import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 지도 아래 시트 틀(시안 `.m-sheet`) — 윗면만 둥글고 위로 뻗는 그림자, 맨 위에 손잡이.
///
/// 내용이 화면 6할을 넘으면 시트 안에서만 스크롤한다(글자를 키운 폰에서 지도가 시트에 먹히지 않게).
/// [children] 사이는 12 씩 띄운다.
class MapSheetFrame extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);

    return Semantics(
      container: true,
      label: '버스 정보',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(BaraedaRadius.sheet),
          ),
          boxShadow: BaraedaShadows.sheet,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.6),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              BaraedaSpacing.gutterMobile,
              BaraedaSpacing.space2,
              BaraedaSpacing.gutterMobile,
              BaraedaSpacing.space4 + media.padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.borderDefault,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const SizedBox(width: 40, height: 5),
                  ),
                ),
                for (final child in children) ...[
                  const SizedBox(height: BaraedaSpacing.space3),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 시트 맨 윗줄 — 누구 버스인지(둥근 머리글자 + 제목 + 부제)와 오른쪽 상태 칩(시안 `.p-who`).
class MapSheetWho extends StatelessWidget {
  const new({
    required this.initial,
    required this.title,
    required this.chipLabel,
    required this.chipStatus,
    this.subtitle,
    super.key,
  });

  /// 둥근 칸 안 한 글자 — 자녀 이름 첫 글자, 학생 본인은 "나".
  final String initial;
  final String title;
  final String? subtitle;
  final String chipLabel;
  final BaraedaStatus chipStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitleText = subtitle;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accentPrimary,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    initial,
                    style: BaraedaTypography.body.copyWith(
                      color: colors.textInverse,
                      fontWeight: BaraedaFontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: BaraedaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WordWrapText(
                  title,
                  style: BaraedaTypography.body.copyWith(
                    fontWeight: BaraedaFontWeight.bold,
                    height: 1.3,
                  ),
                ),
                if (subtitleText != null)
                  WordWrapText(
                    subtitleText,
                    style: BaraedaTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BaraedaSpacing.space2),
          BaraedaStatusPill(
            status: chipStatus,
            label: chipLabel,
            size: BaraedaStatusPillSize.lg,
          ),
        ],
      ),
    );
  }
}

/// 한 칸 — 굵은 값 하나 + 작은 설명(시안 `.m-facts > div`).
typedef MapSheetFact = ({String value, String caption});

/// 시트의 두 칸 요약 — 위에 가는 선, 둘 사이에도 가는 세로선(시안 `.m-facts`).
class MapSheetFacts extends StatelessWidget {
  const new({required this.facts, super.key});

  final List<MapSheetFact> facts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < facts.length; i++)
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(
                              left: BorderSide(color: colors.borderSubtle),
                            ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : BaraedaSpacing.space3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WordWrapText(
                            facts[i].value,
                            style: BaraedaTypography.body.copyWith(
                              fontWeight: BaraedaFontWeight.bold,
                              height: 1.3,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          WordWrapText(
                            facts[i].caption,
                            style: BaraedaTypography.caption.copyWith(
                              color: colors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 불러오는 중 시트 뼈대(시안 `live-map--loading`) — 누구 줄 · 두 칸 · 꺼진 [노선 자세히 보기].
class MapSheetSkeleton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '버스 위치를 불러오는 중',
      child: const ExcludeSemantics(
        child: MapSheetFrame(
          children: [
            Row(
              children: [
                BaraedaSkeleton(width: 44, height: 44, radius: 22),
                SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BaraedaSkeleton(width: 120),
                      SizedBox(height: BaraedaSpacing.space2),
                      BaraedaSkeleton(width: 90, height: 12),
                    ],
                  ),
                ),
                BaraedaSkeleton(width: 64, height: 32, radius: 16),
              ],
            ),
            Row(
              children: [
                Expanded(child: _SkeletonFact()),
                SizedBox(width: BaraedaSpacing.space4),
                Expanded(child: _SkeletonFact()),
              ],
            ),
            BaraedaButton(
              label: '노선 자세히 보기',
              variant: BaraedaButtonVariant.secondary,
              block: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonFact extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BaraedaSkeleton(width: 90),
        SizedBox(height: BaraedaSpacing.space2),
        BaraedaSkeleton(width: 110, height: 12),
      ],
    );
  }
}
