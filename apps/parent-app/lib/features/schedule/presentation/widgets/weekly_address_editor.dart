import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/widgets/sticky_action_bar.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';

/// §3.7 요일×방향 주소 편집기 — 요일 알약(월~일) 하나를 고르면 그 요일의 등원 · 하원 두 칸이 나온다(R48).
///
/// 저장은 **전체 일괄**이다(서버가 한 칸이라도 비면 전체를 거절, F05-11). 그래서 저장하지 않은 요일에는 점을 달고
/// 위에 "저장하지 않은 변경이 있어요" 띠를 둔다. 저장 단추는 아래에 고정이다.
///
/// **기본 주소 개념이 부재하다(C-12)** — 서버가 이미 갖고 있는 요일×방향
/// 조합만 편집한다. 등록된 주소가 하나도 없을 때만 [추가] 로 첫 조합 하나를 넣을 수 있다
/// (R32 P11 — 편집할 칸이 없어 주소를 넣을 방법이 없었다). 조합을 더 늘리는 UI 는 범위 밖.
class WeeklyAddressEditor extends ConsumerStatefulWidget {
  const new({required this.studentId, required this.entries, super.key});

  final String studentId;
  final List<WeeklyAddressEntry> entries;

  @override
  ConsumerState<WeeklyAddressEditor> createState() =>
      _WeeklyAddressEditorState();
}

class _WeeklyAddressEditorState extends ConsumerState<WeeklyAddressEditor> {
  final Map<String, TextEditingController> _controllers = {};

  /// 지금 보고 있는 요일 — 요일을 바꿔도 다른 요일에 적은 글자는 그대로 둔다(저장은 전체 일괄, F05-11).
  Weekday? _selectedDay;

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

  /// 저장하지 않은 글자가 있는 요일 — 요일 알약의 점이 된다.
  Set<Weekday> get _dirtyDays => {
    for (final entry in widget.entries)
      if (_controllerFor(entry).text != _baseline[_keyFor(entry)])
        entry.weekday,
  };

  /// 저장하지 않은 입력이 있는지 일정 화면에 알린다(뒤로가기 확인용) — 요일 알약의 점과 띠도 글자를 따라간다.
  void _reportDirty() {
    _edits.mark(this, dirty: _isDirty);
    if (mounted) setState(() {});
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
    // F05-11 — 한 칸만 비어도 서버가 전체(최대 14건)를 거절해 다른 요일 수정분까지 잃는다. 보내기 전에 막는다.
    // 잠금(`_submitting`)은 이 검사 뒤에 건다 — 앞에서 걸면 경고 뒤 저장 버튼이 영구히 잠긴다(R46).
    if (widget.entries.any((e) => _controllerFor(e).text.trim().isEmpty)) {
      setState(() {
        _bannerTone = AlertTone.missed;
        _banner = '비어 있는 주소가 있습니다. 주소를 입력해 주세요';
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
        _banner = '저장했어요';
      });
      // 저장한 글자가 새 기준이다 — 이후로는 고친 것이 없으므로 뒤로가기 확인이 뜨지 않는다.
      for (final entry in widget.entries) {
        _baseline[_keyFor(entry)] = _controllerFor(entry).text;
      }
      // 점을 지운다 — 저장한 글자가 새 기준이다.
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

    final days = {for (final e in widget.entries) e.weekday}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final selected = days.contains(_selectedDay) ? _selectedDay! : days.first;
    final dirtyDays = _dirtyDays;
    final entriesOfDay = widget.entries
        .where((e) => e.weekday == selected)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.gutterMobile,
            ),
            children: [
              const Text('요일별 등하원 주소', style: BaraedaTypography.h2),
              const SizedBox(height: BaraedaSpacing.space1),
              Text(
                '매주 같은 요일에는 이 주소로 버스가 와요.',
                style: BaraedaTypography.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaSegmentedControl(
                block: true,
                options: [
                  for (final day in days)
                    BaraedaSegmentedOption(
                      day.wireValue,
                      // 저장하지 않은 요일은 점으로 알린다 — 색만으로 뜻을 싣지 않도록 글자(●)로 단다.
                      label: dirtyDays.contains(day)
                          ? '${day.label}●'
                          : day.label,
                    ),
                ],
                value: selected.wireValue,
                onChanged: (value) =>
                    setState(() => _selectedDay = Weekday.fromWireValue(value)),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              if (dirtyDays.isNotEmpty) ...[
                const AlertBanner(
                  tone: AlertTone.moving,
                  title: '저장하지 않은 변경이 있어요',
                  body: '저장해야 노선에 반영돼요.',
                ),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              for (final entry in entriesOfDay) ...[
                BaraedaInput(
                  // 고정 키 — 첫 글자를 치면 위에 "저장하지 않은 변경" 띠가 끼어드는데, 키가 없으면 입력칸이
                  // 새로 만들어져 포커스를 잃고 키보드가 닫힌다.
                  key: ValueKey('weekly-input-${_keyFor(entry)}'),
                  label: '${selected.longLabel} · ${entry.direction.label}',
                  controller: _controllerFor(entry),
                ),
                const SizedBox(height: BaraedaSpacing.space2),
              ],
              Text(
                '저장하면 주소를 확인한 뒤 노선에 반영해요',
                style: BaraedaTypography.bodySm.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              if (_banner != null) ...[
                const SizedBox(height: BaraedaSpacing.space2),
                AlertBanner(tone: _bannerTone, body: _banner),
              ],
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaListGroup(
                children: [
                  BaraedaListRow(
                    leadingIcon: 'pencil',
                    title: '하루만 바꾸고 싶어요',
                    subtitle: '일일 변경을 쓰면 그날만 바뀌어요',
                    trailing: const BaraedaIcon('chevron-right', size: 20),
                    onTap: () => context.push(AppRoutes.dailyChange),
                  ),
                ],
              ),
              const SizedBox(height: BaraedaSpacing.space4),
            ],
          ),
        ),
        StickyActionBar(
          child: BaraedaButton(
            label: '저장하기',
            block: true,
            onPressed: _submitting ? null : _save,
          ),
        ),
      ],
    );
  }

  /// 등록된 주소가 없을 때 — 안내와 [추가]. 누르면 요일·방향·주소 입력을 연다.
  Widget _buildEmpty() {
    if (!_adding) {
      return Center(
        child: EmptyState(
          title: '등록된 등하원 주소가 없어요',
          action: BaraedaButton(
            label: '추가',
            onPressed: () => setState(() => _adding = true),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
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
                    BaraedaSelectOption(
                      direction.wireValue,
                      label: direction.label,
                    ),
                ],
                onChanged: (value) => setState(
                  () => _draftDirection = RunDirection.fromWireValue(
                    value ?? 'to_academy',
                  ),
                ),
              ),
              const SizedBox(height: BaraedaSpacing.space2),
              BaraedaInput(label: '주소', controller: _draftController),
              if (_banner != null) ...[
                const SizedBox(height: BaraedaSpacing.space2),
                AlertBanner(tone: _bannerTone, body: _banner),
              ],
            ],
          ),
        ),
        StickyActionBar(
          child: BaraedaButton(
            label: '저장하기',
            block: true,
            onPressed: _submitting ? null : _save,
          ),
        ),
      ],
    );
  }
}
