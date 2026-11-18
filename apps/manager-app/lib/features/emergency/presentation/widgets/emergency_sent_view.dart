import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_time_label.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_views.dart';

/// 비상 알림을 보낸 직후 화면 본문(시안 `emergency--sent`) — 발송 카드 · 진행 단계 · 전화.
class EmergencySentView extends StatelessWidget {
  const new({
    required this.raised,
    required this.typeLabel,
    required this.cancelErrorMessage,
    required this.canceling,
    required this.onCancel,
    super.key,
  });

  final EmergencyRaiseResult raised;
  final String typeLabel;
  final String? cancelErrorMessage;
  final bool canceling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cancelErrorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: cancelErrorMessage),
          const SizedBox(height: 12),
        ],
        EmergencyStatusCard(
          title: '비상 알림을 보냈어요',
          subtitle:
              '학원 관계자·메인 관리자 ${raised.notified}명에게 전달 · $typeLabel · '
              '${emergencyTimeLabel(raised.raisedAt)}',
          below: [
            EmergencyCancelWindow(
              raisedAt: raised.raisedAt,
              cancelableUntil: raised.cancelableUntil,
              canceling: canceling,
              onCancel: onCancel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const EmergencySteps(
          steps: [
            EmergencyStep(title: '발송 완료', detail: '위치 · 회차 · 연락처가 함께 갔어요'),
            EmergencyStep(
              title: '학원이 확인하면 여기에 표시돼요',
              detail: '확인되면 "○○ 님이 확인함" 으로 바뀌어요',
              done: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const EmergencyCallButton(),
      ],
    );
  }
}
