// 탑승자 명단의 한 줄 — 매니저 앱 정류장별 명단, 관계자 웹 학생 명부 공통.
// 원본: `frontend/design-system/components/transit/StudentRow.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:flutter/material.dart';

/// 동승자 앱이 결정하는 탑승 상태.
enum RideStatus { boarded, alighted, absent, missed, waiting }

class _RideMeta {
  const _RideMeta(this.label, this.status);

  final String label;
  final BaraedaStatus status;

  static const _table = {
    RideStatus.boarded: _RideMeta('탑승 완료', BaraedaStatus.boarded),
    RideStatus.alighted: _RideMeta('하차 완료', BaraedaStatus.boarded),
    RideStatus.absent: _RideMeta('미등원', BaraedaStatus.idle),
    RideStatus.missed: _RideMeta('미탑승', BaraedaStatus.missed),
    RideStatus.waiting: _RideMeta('대기', BaraedaStatus.idle),
  };

  static _RideMeta of(RideStatus ride) => _table[ride]!;
}

/// 탑승자 명단 한 줄.
class StudentRow extends StatelessWidget {
  const StudentRow({
    super.key,
    this.name,
    this.meta,
    this.phone,
    this.ride = RideStatus.waiting,
    this.selected = false,
    this.onSelect,
    this.onCall,
    this.actions,
  });

  final String? name;

  /// 정류장 · 반 · 보호자 등 한 줄.
  final String? meta;
  final String? phone;
  final RideStatus ride;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onCall;

  /// 상태 pill 대신 넣을 컨트롤(탑승/미등원/하차 전환 버튼).
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rideMeta = _RideMeta.of(ride);
    final initials = name != null && name!.length >= 2
        ? name!.substring(name!.length - 2)
        : (name ?? '');

    return Semantics(
      button: onSelect != null,
      selected: selected,
      label: [name, meta].whereType<String>().join(' · '),
      child: Material(
        color: selected ? colors.bgSubtle : colors.surfaceCard,
        child: InkWell(
          onTap: onSelect,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space4,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.bgSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials,
                    style: BaraedaTypography.labelSm.copyWith(
                      fontSize: 14,
                      height: 1,
                      fontWeight: BaraedaFontWeight.bold,
                      color: colors.textBrand,
                    ),
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (name != null)
                        Text(
                          name!,
                          style: BaraedaTypography.bodySm.copyWith(
                            height: 1.4,
                            fontWeight: BaraedaFontWeight.medium,
                          ),
                        ),
                      if (meta != null)
                        Text(
                          meta!,
                          style: BaraedaTypography.micro.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (phone != null && onCall != null)
                  Padding(
                    padding: const EdgeInsets.only(left: BaraedaSpacing.space2),
                    child: _CallButton(onCall: onCall!),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: BaraedaSpacing.space2),
                  child:
                      actions ??
                      BaraedaStatusPill(
                        status: rideMeta.status,
                        label: rideMeta.label,
                        dot: false,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.onCall});

  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '보호자에게 연락',
      child: Material(
        color: colors.surfaceCard,
        shape: CircleBorder(side: BorderSide(color: colors.borderSubtle)),
        child: InkWell(
          onTap: onCall,
          customBorder: const CircleBorder(),
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: BaraedaIcon(
                'phone',
                size: 16,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
