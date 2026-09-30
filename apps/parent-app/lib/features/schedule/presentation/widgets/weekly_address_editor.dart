import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';

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

  /// 저장했거나 불러온 시점의 글자 — 이것과 다르면 저장하지 않은 입력이다(P14).
  final Map<String, String> _baseline = {};
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// dispose 에서는 `ref` 를 못 쓰므로 미리 잡아 둔다.
  late final UnsavedEdits _edits;

  @override
  void initState() {
    super.initState();
    _edits = ref.read(scheduleUnsavedEditsProvider);
    _draftController.addListener(_reportDirty);
  }

  /// 항목마다 입력 controller 를 처음 필요할 때 만든다 — 저장 뒤 목록이 새로 오면 새 조합이 생길 수 있다.
  TextEditingController _controllerFor(WeeklyAddressEntry entry) =>
      _controllers.putIfAbsent(_keyFor(entry), () {
        _baseline[_keyFor(entry)] = entry.address;
        return TextEditingController(text: entry.address)
          ..addListener(_reportDirty);
      });

  bool get _isDirty => widget.entries.isEmpty
      ? _draftController.text.trim().isNotEmpty
      : widget.entries.any(
          (entry) => _controllerFor(entry).text != _baseline[_keyFor(entry)],
        );

  /// 저장하지 않은 입력이 있는지 일정 화면에 알린다(뒤로가기 확인용).
  void _reportDirty() {
    _edits.mark(this, dirty: _isDirty);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _draftController.dispose();
    super.dispose();
    // 화면이 그려지는 도중에 구독자(일정 화면)를 흔들지 않도록 한 박자 뒤에 지운다.
    scheduleMicrotask(() => _edits.mark(this, dirty: false));
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

    // F05-11 — 한 칸만 비어도 서버가 전체(최대 14건)를 거절해 다른 요일 수정분까지 잃는다. 보내기 전에 막는다.
    if (widget.entries.any((e) => _controllerFor(e).text.trim().isEmpty)) {
      setState(() {
        _bannerTone = AlertTone.missed;
        _banner = '비어 있는 주소가 있습니다. 주소를 입력해 주세요';
      });
      return;
    }

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
                (entry) =>
                    entry.copyWith(address: _controllerFor(entry).text.trim()),
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
      // 저장한 글자가 새 기준이다 — 이후로는 고친 것이 없으므로 뒤로가기 확인이 뜨지 않는다.
      for (final entry in widget.entries) {
        _baseline[_keyFor(entry)] = _controllerFor(entry).text;
      }
      _draftController.clear();
      _reportDirty();
      ref.invalidate(weeklyAddressProvider(widget.studentId));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(code: 'ADDRESS_VERIFICATION_FAILED') =>
            '주소를 확인할 수 없습니다. 다시 입력해 주세요',
          _ => failureMessage(failure, fallback: '저장하지 못했습니다'),
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
