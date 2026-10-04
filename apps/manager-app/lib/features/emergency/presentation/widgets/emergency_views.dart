import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/countdown_tick.dart';

/// 결과 화면 맨 위 카드(시안 `emergency--sent` · `--ack`) — 체크 표식 · 제목 ·
/// 한 줄 설명, 그 아래 [below].
class EmergencyStatusCard extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    this.below = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BaraedaCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.statusBoardedSoft,
                  borderRadius: BorderRadius.circular(BaraedaRadius.control),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: BaraedaIcon(
                      'check',
                      size: 24,
                      color: colors.statusBoarded,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: BaraedaTypography.h3.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final child in below) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            child,
          ],
        ],
      ),
    );
  }
}

/// `취소할 수 있는 시간 0:42 남음` + 줄어드는 막대 + `보낸 알림 취소`(시안
/// `emergency--sent`). 취소 가능 시각은 서버가 준 `cancelable_until` 이다 —
/// 창이 닫혔으면(지났으면) 아무것도 그리지 않는다.
class EmergencyCancelWindow extends ConsumerWidget {
  const new({
    required this.raisedAt,
    required this.cancelableUntil,
    required this.canceling,
    required this.onCancel,
    super.key,
  });

  final DateTime raisedAt;
  final DateTime cancelableUntil;
  final bool canceling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = cancelableUntil.difference(
      ref.watch(clockProvider).now(),
    );
    if (!remaining.isNegative && remaining > Duration.zero) {
      // 창이 열려 있는 동안만 1초 신호를 듣는다 — 닫히면 타이머가 멈춘다.
      ref.watch(countdownTickProvider);
    } else {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final total = cancelableUntil.difference(raisedAt).inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (remaining.inMilliseconds / total).clamp(0.0, 1.0);
    final seconds =
        remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    final text =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} 남음';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '취소할 수 있는 시간',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Text(
              text,
              style: BaraedaTypography.label.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                ColoredBox(
                  color: colors.accentPrimarySoft,
                  child: const SizedBox.expand(),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: ColoredBox(
                    color: colors.accentPrimary,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space3),
        BaraedaButton(
          label: '보낸 알림 취소',
          variant: BaraedaButtonVariant.secondary,
          block: true,
          onPressed: canceling ? null : onCancel,
        ),
      ],
    );
  }
}

/// 진행 단계 한 칸.
class EmergencyStep {
  const new({required this.title, required this.detail, this.done = true});

  final String title;
  final String detail;

  /// `true` 면 체크가 든 진한 원, `false` 면 앰버 고리와 순번.
  final bool done;
}

/// `발송 완료` → `학원이 확인함` 두 단계 표시(시안 `emergency--sent` · `--ack`).
class EmergencySteps extends StatelessWidget {
  const new({required this.steps, super.key});

  final List<EmergencyStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BaraedaCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        _StepDot(
                          number: i + 1,
                          done: steps[i].done,
                          colors: colors,
                        ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: colors.borderDefault,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BaraedaSpacing.space3),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < steps.length - 1
                            ? BaraedaSpacing.space4
                            : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            steps[i].title,
                            style: BaraedaTypography.body.copyWith(
                              color: colors.textPrimary,
                              fontWeight: BaraedaFontWeight.bold,
                            ),
                          ),
                          Text(
                            steps[i].detail,
                            style: BaraedaTypography.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const new({required this.number, required this.done, required this.colors});

  final int number;
  final bool done;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? colors.accentPrimary : colors.statusMovingSoft,
        border: Border.all(
          color: done ? colors.accentPrimary : colors.statusMoving,
          width: 2,
        ),
      ),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: done
              ? const BaraedaIcon('check', size: 16, color: Colors.white)
              : Text(
                  '$number',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.statusMoving,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

/// `학원에 전화 · 032-000-1100` 큰 단추(시안 `emergency--sent` · `--failed` ·
/// `--ack`). 학원 번호가 번호 모양이 아니면 걸리지 않는 단추를 그리지 않는다.
class EmergencyCallButton extends ConsumerWidget {
  const new({this.danger = false, super.key});

  /// 전송 실패 화면 — 붉은 면으로 더 눈에 띄게 한다.
  final bool danger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(academyContactProvider);
    if (!looksLikePhoneNumber(contact)) return const SizedBox.shrink();
    final number = contact!.trim();
    return BaraedaButton(
      label: '학원에 전화 · $number',
      icon: 'phone',
      variant: danger
          ? BaraedaButtonVariant.danger
          : BaraedaButtonVariant.primary,
      size: BaraedaButtonSize.xl,
      block: true,
      onPressed: () => unawaited(
        ref.read(uriOpenerProvider)(Uri(scheme: 'tel', path: number)),
      ),
    );
  }
}
