import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_run_choices.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_zone_notice.dart';

/// 일일 변경 신청 입력 목록 — 날짜 · 회차 · 변경 종류 · 주소 · 사유와 오류 안내까지.
///
/// 값은 모두 바깥(State)이 쥐고, 이 위젯은 그리기와 변경 알림만 맡는다.
class ChangeRequestForm extends StatelessWidget {
  const new({
    required this.dayOffset,
    required this.onDayChanged,
    required this.runsAsync,
    required this.selectedRun,
    required this.selectedRunId,
    required this.onRunSelected,
    required this.type,
    required this.onTypeChanged,
    required this.addressController,
    required this.reasonController,
    required this.banner,
    required this.bannerTone,
    super.key,
  });

  /// 0 = 오늘, 1 = 내일 (한국 시간).
  final int dayOffset;
  final ValueChanged<int> onDayChanged;
  final AsyncValue<List<StudentRun>> runsAsync;

  /// 고른 회차 — 그날 회차 목록에 없으면 null.
  final StudentRun? selectedRun;
  final String? selectedRunId;
  final ValueChanged<String> onRunSelected;
  final ChangeRequestType type;
  final ValueChanged<ChangeRequestType> onTypeChanged;
  final TextEditingController addressController;
  final TextEditingController reasonController;
  final String? banner;
  final AlertTone bannerTone;

  @override
  Widget build(BuildContext context) {
    final run = selectedRun;
    return ListView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      children: [
        _DayPicker(dayOffset: dayOffset, onChanged: onDayChanged),
        const SizedBox(height: BaraedaSpacing.space4),
        const _FieldTitle('어느 회차예요?'),
        runsAsync.when(
          skipError: true,
          loading: () => const BaraedaSkeletonList(count: 2),
          error: (error, stack) =>
              const AlertBanner(tone: AlertTone.missed, body: '회차를 불러오지 못했어요'),
          data: (runs) => runs.isEmpty
              ? const WordWrapText('그날 운행이 아직 없어요')
              : ChangeRequestRunChoices(
                  runs: runs,
                  selectedRunId: selectedRunId,
                  onSelected: onRunSelected,
                ),
        ),
        if (run != null) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          ChangeZoneNotice(run: run),
          const SizedBox(height: BaraedaSpacing.space4),
          const _FieldTitle('어떻게 바꿀까요?'),
          _TypePicker(type: type, onChanged: onTypeChanged),
          if (type == ChangeRequestType.relocate) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            BaraedaInput(label: '변경할 주소', controller: addressController),
            const SizedBox(height: BaraedaSpacing.space1),
            Text(
              '주소를 확인한 뒤 노선에 반영해요',
              style: BaraedaTypography.bodySm.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: BaraedaSpacing.space3),
          BaraedaTextarea(label: '사유 (선택)', controller: reasonController),
        ],
        if (banner != null) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          AlertBanner(tone: bannerTone, body: banner),
        ],
      ],
    );
  }
}

/// 신청할 날짜 — 오늘·내일 두 가지.
class _DayPicker extends StatelessWidget {
  const new({required this.dayOffset, required this.onChanged});

  final int dayOffset;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return BaraedaSegmentedControl(
      block: true,
      options: const [
        BaraedaSegmentedOption('0', label: '오늘'),
        BaraedaSegmentedOption('1', label: '내일'),
      ],
      value: '$dayOffset',
      onChanged: (value) => onChanged(int.parse(value)),
    );
  }
}

/// 변경 종류 — 탑승 취소 · 승하차지 변경.
class _TypePicker extends StatelessWidget {
  const new({required this.type, required this.onChanged});

  final ChangeRequestType type;
  final ValueChanged<ChangeRequestType> onChanged;

  @override
  Widget build(BuildContext context) {
    return BaraedaSegmentedControl(
      block: true,
      options: const [
        BaraedaSegmentedOption('cancel', label: '탑승 취소'),
        BaraedaSegmentedOption('relocate', label: '승하차지 변경'),
      ],
      value: type.wireValue,
      onChanged: (value) => onChanged(ChangeRequestType.fromWireValue(value)),
    );
  }
}

class _FieldTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Text(
        text,
        style: BaraedaTypography.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: BaraedaFontWeight.bold,
        ),
      ),
    );
  }
}
