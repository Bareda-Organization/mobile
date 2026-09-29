import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';

/// §3.7 요일×방향 주소 편집기.
///
/// **기본 주소 개념이 부재하다(C-12)** — 서버가 이미 갖고 있는 요일×방향
/// 조합만 편집한다. 등록된 주소가 하나도 없을 때만 [추가] 로 첫 조합 하나를 넣을 수 있다
/// (R32 P11 — 편집할 칸이 없어 주소를 넣을 방법이 없었다). 조합을 더 늘리는 UI 는 범위 밖.
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
  final Map<String, TextEditingController> _controllers = {};

  /// 빈 목록에서 [추가] 를 눌러 연 첫 주소 입력 — 요일·방향·주소.
  bool _adding = false;
  Weekday _draftWeekday = Weekday.mon;
  RunDirection _draftDirection = RunDirection.toAcademy;
  final _draftController = TextEditingController();
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// 항목마다 입력 controller 를 처음 필요할 때 만든다 — 저장 뒤 목록이 새로 오면 새 조합이 생길 수 있다.
  TextEditingController _controllerFor(WeeklyAddressEntry entry) =>
      _controllers.putIfAbsent(
        _keyFor(entry),
        () => TextEditingController(text: entry.address),
      );

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _draftController.dispose();
    super.dispose();
  }

  String _keyFor(WeeklyAddressEntry entry) =>
      '${entry.weekday.wireValue}_${entry.direction.wireValue}';

  Future<void> _save() async {
    if (_submitting) return;
    final draftAddress = _draftController.text.trim();
    if (widget.entries.isEmpty && draftAddress.isEmpty) {
      setState(() {
        _bannerTone = AlertTone.missed;
        _banner = '주소를 입력해 주세요';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _banner = null;
    });

    final updated = widget.entries.isEmpty
        ? [
            WeeklyAddressEntry(
              weekday: _draftWeekday,
              direction: _draftDirection,
              address: draftAddress,
            ),
          ]
        : widget.entries
              .map(
                (entry) => entry.copyWith(address: _controllerFor(entry).text),
              )
              .toList();

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
    if (widget.entries.isEmpty) return _buildEmpty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in widget.entries) ...[
          BaraedaInput(
            label: '${entry.weekday.label} · ${entry.direction.label}',
            controller: _controllerFor(entry),
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

  /// 등록된 주소가 없을 때 — 안내와 [추가]. 누르면 요일·방향·주소 입력을 연다.
  Widget _buildEmpty() {
    if (!_adding) {
      return EmptyState(
        title: '등록된 등하원 주소가 없습니다',
        action: BaraedaButton(
          label: '추가',
          onPressed: () => setState(() => _adding = true),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaSelect(
          label: '요일',
          value: _draftWeekday.wireValue,
          options: [
            for (final day in Weekday.values)
              BaraedaSelectOption(day.wireValue, label: day.label),
          ],
          onChanged: (value) => setState(
            () => _draftWeekday = Weekday.fromWireValue(value ?? 'mon'),
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSelect(
          label: '방향',
          value: _draftDirection.wireValue,
          options: [
            for (final direction in RunDirection.values)
              BaraedaSelectOption(direction.wireValue, label: direction.label),
          ],
          onChanged: (value) => setState(
            () => _draftDirection = RunDirection.fromWireValue(
              value ?? 'to_academy',
            ),
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaInput(label: '주소', controller: _draftController),
        const SizedBox(height: BaraedaSpacing.space2),
        if (_banner != null) ...[
          AlertBanner(tone: _bannerTone, body: _banner),
          const SizedBox(height: BaraedaSpacing.space2),
        ],
        BaraedaButton(label: '저장하기', onPressed: _submitting ? null : _save),
      ],
    );
  }
}
