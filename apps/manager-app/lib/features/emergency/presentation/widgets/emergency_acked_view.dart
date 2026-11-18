import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_item.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_time_label.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_views.dart';

/// 학원이 확인한 뒤 화면 본문(시안 `emergency--ack`) — 확인 카드 · 진행 단계 · 안내.
///
/// 확인된 뒤에도 발신 1분 안이면 [취소] 를 남긴다(887②) — 서버(`§4.14`)가 받는 오발신 철회 수단이다.
class EmergencyAckedView extends StatelessWidget {
  const new({
    required this.item,
    required this.now,
    required this.cancelErrorMessage,
    required this.canceling,
    required this.onCancel,
    super.key,
  });

  final EmergencyItem item;
  final DateTime now;
  final String? cancelErrorMessage;
  final bool canceling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cancelable =
        item.canceledAt == null && now.isBefore(item.cancelableUntil);
    final by = item.ackedByName;
    final who = (by == null || by.isEmpty) ? '학원' : '$by 관계자';
    final ackedAt = item.ackedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cancelErrorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: cancelErrorMessage),
          const SizedBox(height: 12),
        ],
        EmergencyStatusCard(
          title: '학원이 확인했어요',
          subtitle:
              '$who · '
              '${ackedAt == null ? '' : '${emergencyTimeLabel(ackedAt)} · '}'
              '${item.type.label}',
          below: [
            if (cancelable) ...[
              EmergencyCancelWindow(
                raisedAt: item.raisedAt,
                cancelableUntil: item.cancelableUntil,
                canceling: canceling,
                onCancel: onCancel,
              ),
              const SizedBox(height: 12),
            ],
            const EmergencyCallButton(),
          ],
        ),
        const SizedBox(height: 12),
        EmergencySteps(
          steps: [
            EmergencyStep(
              title: '발송 완료',
              detail:
                  '${emergencyTimeLabel(item.raisedAt)} · '
                  '위치 · 회차 · 연락처가 함께 갔어요',
            ),
            EmergencyStep(
              title: '학원이 확인함',
              detail: [
                ?ackedAt == null ? null : emergencyTimeLabel(ackedAt),
                who,
              ].join(' · '),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '운행은 그대로 이어져요. 상황이 바뀌면 학원에 전화로 알려 주세요.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
