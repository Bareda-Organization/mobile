// 원본 `design-system/components/forms/Switch.jsx` 대응.
//
// 원본 CSS는 thumb를 항상 고정 흰색(`#fff`)으로 못박아 둔다. `tokens/colors.dart`의
// 원시 팔레트를 위젯에서 직접 참조하지 않는다는 규칙(같은 파일 헤더 주석) 때문에
// `Colors.white`를 그대로 쓰지 않고, 의미 계층에서 가장 가까운 카드 표면 톤인
// `colors.surfaceRaised`로 대체했다 — 라이트 테마에서는 사실상 흰색과 같고,
// 다크 테마에서도 트랙보다 밝은 표면이라는 시각 관계는 유지된다.
import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 온/오프 스위치 + 라벨 한 줄. `BaraedaCheckbox`와 같은 prop 구성이다.
class BaraedaSwitch extends StatelessWidget {
  const BaraedaSwitch({
    required this.checked,
    required this.label,
    super.key,
    this.sublabel,
    this.onChanged,
    this.disabled = false,
  });

  final bool checked;
  final String label;
  final String? sublabel;
  final ValueChanged<bool>? onChanged;
  final bool disabled;

  bool get _effectivelyDisabled => disabled || onChanged == null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      toggled: checked,
      enabled: !_effectivelyDisabled,
      label: label,
      child: Opacity(
        opacity: _effectivelyDisabled ? 0.42 : 1,
        child: InkWell(
          onTap: _effectivelyDisabled ? null : () => onChanged!(!checked),
          hoverColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: BaraedaTypography.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (sublabel != null)
                        Text(
                          sublabel!,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SwitchTrack(checked: checked, colors: colors),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTrack extends StatelessWidget {
  const _SwitchTrack({required this.checked, required this.colors});

  final bool checked;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 40,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: checked ? colors.accentPrimary : colors.borderControl,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
