import 'dart:convert';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/ui/info_rows_card.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_time_label.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_views.dart';
import 'package:manager_app/features/offline_queue/domain/models/pending_request_summary.dart';

/// 서버에 닿지 못한 신고 화면 본문(시안 `emergency--failed`) — 안내 · 전화 · 대기 정보 표.
class EmergencyFailedView extends StatelessWidget {
  const new({
    required this.unsent,
    required this.queuedType,
    required this.queuedAt,
    super.key,
  });

  /// 큐에서 아직 안 나간 가장 나중 비상 신고 — 없으면 이 화면에서 누른 [queuedType] · [queuedAt] 을 쓴다.
  final PendingRequestSummary? unsent;
  final EmergencyType? queuedType;
  final DateTime? queuedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = _typeOfQueued(unsent) ?? queuedType;
    final pressedAt = unsent?.createdAt ?? queuedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AlertBanner(
          tone: AlertTone.missed,
          title: '전송 실패 — 계속 다시 보내는 중',
          body: '아직 아무에게도 닿지 않았어요. 급하면 학원에 바로 전화해 주세요.',
        ),
        const SizedBox(height: 12),
        const EmergencyCallButton(danger: true),
        const SizedBox(height: 12),
        InfoRowsCard(
          rows: [
            InfoRow('유형', value: type?.label ?? '비상 알림'),
            if (pressedAt != null)
              InfoRow('누른 시각', value: emergencyTimeLabel(pressedAt)),
            InfoRow(
              '상태',
              valueWidget: Row(
                children: [
                  const BaraedaStatusPill(
                    status: BaraedaStatus.waiting,
                    label: '전송 대기',
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '연결되면 자동 전송',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        WordWrapText(
          '비상 알림은 포기하지 않고 성공할 때까지 다시 보내요. 서버에는 누른 시각이 아니라 받은 시각이 기록돼요. '
          '못 보낸 처리는 내 정보 ▸ 오프라인 대기열에서도 볼 수 있어요.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 큐에 쌓인 신고 본문(`{"type":"accident",…}`)에서 유형을 읽는다 — 읽지 못하면 `null`.
EmergencyType? _typeOfQueued(PendingRequestSummary? request) {
  if (request == null) return null;
  try {
    final decoded = jsonDecode(request.payload);
    if (decoded is Map<String, dynamic>) {
      return EmergencyType.fromWireValueOrNull(decoded['type'] as String?);
    }
  } on FormatException {
    return null;
  }
  return null;
}
