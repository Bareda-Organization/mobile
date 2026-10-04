import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';

/// 번호로 보이는 문자열인가 — 숫자 7개 이상이고 숫자·`+`·`-`·`()`·공백만 있다.
/// 학원이 연락처 칸에 문장을 적어 둔 경우 전화 단추를 만들지 않으려고 거른다(`Ruling 827`).
bool looksLikePhoneNumber(String? value) {
  if (value == null) return false;
  final text = value.trim();
  if (!RegExp(r'^[0-9+\-() ]+$').hasMatch(text)) return false;
  return RegExp('[0-9]').allMatches(text).length >= 7;
}

/// `<안내> / 학원 032-000-1100 [전화]` 한 줄 카드 — 불러오기 실패 · 운행 준비 실패에서 학원에 바로 전화한다.
/// 학원 연락처가 번호 모양이 아니면 아무것도 그리지 않는다.
class AcademyCallCard extends ConsumerWidget {
  const new({required this.lead, super.key});

  /// 굵은 첫 줄 — `운행 시작이 급하면` 같은 상황 문구.
  final String lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(academyContactProvider);
    if (!looksLikePhoneNumber(contact)) return const SizedBox.shrink();
    final number = contact!.trim();
    final colors = context.colors;
    return BaraedaCard(
      tone: BaraedaCardTone.mist,
      child: Row(
        children: [
          BaraedaIcon('phone', color: colors.textBrand),
          const SizedBox(width: BaraedaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WordWrapText(
                  lead,
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textBrand,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
                WordWrapText(
                  '학원 $number',
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textBrand,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          BaraedaButton(
            label: '전화',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => unawaited(
              ref.read(uriOpenerProvider)(Uri(scheme: 'tel', path: number)),
            ),
          ),
        ],
      ),
    );
  }
}
