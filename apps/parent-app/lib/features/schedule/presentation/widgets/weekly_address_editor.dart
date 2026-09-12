import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';

/// §3.7 요일×방향 주소 편집기.
///
/// **기본 주소 개념이 부재하다(C-12)** — 서버가 이미 갖고 있는 요일×방향
/// 조합만 편집한다. 새 요일 조합 추가 UI 는 이번 범위에 없다(보고서 §2
/// 판단 근거).
class WeeklyAddressEditor extends ConsumerStatefulWidget {
  const WeeklyAddressEditor({
    required this.studentId,
    required this.entries,
    super.key,
  });

  final String studentId;
  final List<WeeklyAddressEntry> entries;

  @override
  ConsumerState<WeeklyAddressEditor> createState() =>
      _WeeklyAddressEditorState();
}

class _WeeklyAddressEditorState extends ConsumerState<WeeklyAddressEditor> {
  late final Map<String, TextEditingController> _controllers;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final entry in widget.entries)
        _keyFor(entry): TextEditingController(text: entry.address),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _keyFor(WeeklyAddressEntry entry) =>
      '${entry.weekday.wireValue}_${entry.direction.wireValue}';

  Future<void> _save() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _banner = null;
    });

    final updated = widget.entries.map((entry) {
      final address = _controllers[_keyFor(entry)]!.text;
      return entry.copyWith(address: address);
    }).toList();

    try {
      await ref
          .read(weeklyAddressRepositoryProvider)
          .updateWeeklyAddress(widget.studentId, updated);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.boarded;
        _banner = '저장했습니다';
      });
      ref.invalidate(weeklyAddressProvider(widget.studentId));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(code: 'ADDRESS_VERIFICATION_FAILED') =>
            '주소를 확인할 수 없습니다. 다시 입력해 주세요',
          ApiFailure(:final message) => message,
          _ => '저장하지 못했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const EmptyState(title: '등록된 등하원 주소가 없습니다');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in widget.entries) ...[
          BaraedaInput(
            label: '${entry.weekday.label} · ${entry.direction.label}',
            controller: _controllers[_keyFor(entry)],
          ),
          const SizedBox(height: BaraedaSpacing.space2),
        ],
        if (_banner != null) ...[
          AlertBanner(tone: _bannerTone, body: _banner),
          const SizedBox(height: BaraedaSpacing.space2),
        ],
        BaraedaButton(
          label: '저장하기',
          onPressed: _submitting ? null : _save,
        ),
      ],
    );
  }
}
