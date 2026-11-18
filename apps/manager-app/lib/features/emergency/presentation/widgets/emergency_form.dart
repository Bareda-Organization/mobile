import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/choice_tile_grid.dart';
import 'package:manager_app/core/ui/info_rows_card.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_type.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

const List<ChoiceTileOption<EmergencyType>> _typeOptions = [
  ChoiceTileOption(
    value: EmergencyType.accident,
    label: '사고',
    icon: 'triangle-alert',
  ),
  ChoiceTileOption(
    value: EmergencyType.vehicleFault,
    label: '차량 고장',
    icon: 'bus',
  ),
  ChoiceTileOption(
    value: EmergencyType.studentEmergency,
    label: '학생 응급',
    icon: 'user-round',
  ),
  ChoiceTileOption(
    value: EmergencyType.etc,
    label: '기타',
    icon: 'info',
    hint: '메모 필수',
  ),
];

/// 비상 작성 화면 본문(시안 `emergency`) — 유형 · 상황 메모 · 함께 보내는 정보.
class EmergencyForm extends ConsumerWidget {
  const new({
    required this.type,
    required this.errorMessage,
    required this.submitting,
    required this.memoController,
    required this.onTypeChanged,
    super.key,
  });

  final EmergencyType type;
  final String? errorMessage;
  final bool submitting;
  final LimitedTextController memoController;
  final ValueChanged<EmergencyType> onTypeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final run = ref.watch(selectedManagerRunProvider);
    final sample = ref.read(positionSourceProvider).sample();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 급하면 먼저 전화 — 번호는 저장된 학원 연락처이고, 번호 모양이 아니면 그리지 않는다.
        const AcademyCallCard(lead: '급하면 먼저 전화하세요'),
        const SizedBox(height: 16),
        if (errorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: errorMessage),
          const SizedBox(height: 12),
        ],
        Text(
          '무슨 일이에요?',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 8),
        ChoiceTileGrid<EmergencyType>(
          options: _typeOptions,
          value: type,
          onChanged: submitting ? null : onTypeChanged,
        ),
        const SizedBox(height: 16),
        BaraedaTextarea(
          label: type == EmergencyType.etc ? '상황 메모 (필수)' : '상황 메모 (선택)',
          hint: '무슨 일이 있었는지 적어 주세요 · $freeTextPrivacyNotice',
          rows: 2,
          enabled: !submitting,
          controller: memoController,
        ),
        const SizedBox(height: 16),
        Text(
          '함께 보내는 정보',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 8),
        InfoRowsCard(
          rows: [
            InfoRow(
              '회차',
              value: run == null
                  ? '선택한 회차'
                  : '${run.busNo} · ${directionLabel(run.direction)} '
                        '${hhmm(run.departTime)}',
            ),
            InfoRow(
              '현재 위치',
              value: sample == null
                  ? '서버가 받은 마지막 위치'
                  : '현재 위치 · ${hhmm(sample.recordedAt)} 측정',
            ),
            const InfoRow('받는 사람', value: '학원 관계자 · 메인 관리자'),
          ],
        ),
      ],
    );
  }
}
