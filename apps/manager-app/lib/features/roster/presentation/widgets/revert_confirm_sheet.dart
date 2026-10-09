import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// 승하차 처리를 되돌리기 전 확인 창(시안 `undo`) — 학생 · 상태 변화 · 남는 일을 보여 주고 `되돌리기` 를 눌러야만
/// `true` 를 돌려준다. `닫기` · 창 밖을 눌러 닫으면 `false` 다.
Future<bool> showRevertConfirmSheet(
  BuildContext context, {
  required RosterStudent student,
}) async {
  final confirmed = await showBaraedaBottomSheet<bool>(
    context: context,
    title: '${_processName(student.status)} 처리를 되돌릴까요?',
    showCloseButton: true,
    builder: (sheetContext) => _RevertConfirmBody(student: student),
  );
  return confirmed ?? false;
}

/// 되돌릴 처리의 이름 — 시안 문구(`승차 처리를 되돌릴까요?`).
String _processName(RiderStatus status) => switch (status) {
  RiderStatus.boarded => '승차',
  RiderStatus.alighted => '하차',
  RiderStatus.noShow => '미승차',
  _ => '승하차',
};

/// 되돌린 뒤의 상태 — 탑승 → 대기, 하차 → 탑승, 미승차 → 대기.
RiderStatus _revertedStatus(RiderStatus status) =>
    status == RiderStatus.alighted ? RiderStatus.boarded : RiderStatus.waiting;

({BaraedaStatus status, String label}) _pillOf(RiderStatus status) =>
    switch (status) {
      RiderStatus.boarded => (status: BaraedaStatus.boarded, label: '탑승'),
      RiderStatus.alighted => (status: BaraedaStatus.idle, label: '하차'),
      RiderStatus.noShow => (status: BaraedaStatus.missed, label: '미승차'),
      _ => (status: BaraedaStatus.waiting, label: '대기'),
    };

class _RevertConfirmBody extends StatelessWidget {
  const new({required this.student});

  final RosterStudent student;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final from = _pillOf(student.status);
    final to = _pillOf(_revertedStatus(student.status));
    final initial = student.name.isEmpty ? '' : student.name.characters.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(BaraedaRadius.control),
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Text(
                    initial,
                    style: BaraedaTypography.title.copyWith(
                      color: colors.textSecondary,
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
                  Text(
                    student.name,
                    style: BaraedaTypography.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (student.className != null)
                    Text(
                      student.className!,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            BaraedaStatusPill(status: from.status, label: from.label),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('→'),
            ),
            BaraedaStatusPill(status: to.status, label: to.label),
          ],
        ),
        const SizedBox(height: BaraedaSpacing.space3),
        _Bullet(spans: [_span('처리 기록은 지워지지 않고 남아요')]),
        // 승차·하차 취소 알림은 없다(Ruling 308) — 미승차를 되돌릴 때만 남는 일이 하나 더 있다.
        if (student.status == RiderStatus.noShow)
          _Bullet(spans: [_span('연락 대기가 끝나고 그 승하차지의 건너뜀이 풀려요')]),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaButton(
          label: '되돌리기',
          size: BaraedaButtonSize.xl,
          block: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaButton(
          label: '닫기',
          variant: BaraedaButtonVariant.secondary,
          block: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const new({required this.spans});

  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('•', style: TextStyle(color: colors.textSecondary)),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: spans),
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 낱말 안에서 줄이 바뀌지 않게 이어 붙인 구간 — 낭독과 글자 찾기는 원문을 쓴다([WordWrapText] 와 같다).
TextSpan _span(String text, {TextStyle? style}) => TextSpan(
  text: WordWrapText.keepWords(text),
  semanticsLabel: text,
  style: style,
);
