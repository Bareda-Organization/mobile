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
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/unsaved_edits.dart';

/// §3.7 요일×방향 주소 편집기 — 요일 알약(월~일) 7개 중 하나를 고르면 그 요일의 등원 · 하원 두 칸이 나온다.
///
/// 요일 7 × 방향 2 = **14칸 전부** 주소와 상세 주소(`address_detail`)를
/// 적을 수 있다(P-05 · STU-06, H5).
/// 서버가 아직 갖고 있지 않은 칸은 빈 칸으로 열리고, 적은 칸만 저장 요청에 실린다(`PATCH` 는 보낸 칸만 반영).
/// 서버에 이미 있던 칸을 비우는 것은 막는다 — 칸을 지우는 수단이 없고 빈 주소는 전체를 거절시킨다(F05-11).
///
/// 저장하지 않은 요일에는 점을 달고 위에 "저장하지 않은 변경이 있어요" 띠를 둔다.
/// 저장 단추는 아래에 고정이다.
///
/// **기본 주소 개념이 부재하다(C-12)** — 요일 × 방향 조합마다 각자의 주소를 갖는다.
class WeeklyAddressEditor extends ConsumerStatefulWidget {
  const new({required this.studentId, required this.entries, super.key});

  final String studentId;
  final List<WeeklyAddressEntry> entries;

  @override
  ConsumerState<WeeklyAddressEditor> createState() =>
      _WeeklyAddressEditorState();
}

/// 요일 × 방향 한 칸의 입력 상태 — 주소와 상세 주소 입력 controller, 그리고 마지막으로 저장했거나 불러온 글자.
class _Slot {
  new({
    required this.weekday,
    required this.direction,
    required String address,
    required String detail,
    required VoidCallback onChanged,
  }) : address = TextEditingController(text: address),
       detail = TextEditingController(text: detail),
       baselineAddress = address,
       baselineDetail = detail {
    this.address.addListener(onChanged);
    this.detail.addListener(onChanged);
  }

  final Weekday weekday;
  final RunDirection direction;
  final TextEditingController address;
  final TextEditingController detail;

  /// 저장했거나 불러온 시점의 글자 — 이것과 다르면 저장하지 않은 입력이다(P14).
  String baselineAddress;
  String baselineDetail;

  /// 서버에 이미 있는 칸인가 — 비우면 안 된다.
  bool get isRegistered => baselineAddress.isNotEmpty;

  bool get isDirty =>
      address.text != baselineAddress || detail.text != baselineDetail;

  void markSaved() {
    baselineAddress = address.text;
    baselineDetail = detail.text;
  }

  void dispose() {
    address.dispose();
    detail.dispose();
  }

  String get key => '${weekday.wireValue}_${direction.wireValue}';
}

class _WeeklyAddressEditorState extends ConsumerState<WeeklyAddressEditor> {
  /// 14칸 — 요일 월~일 × 등원 · 하원 순서.
  late final List<_Slot> _slots;

  /// 지금 보고 있는 요일 — 요일을 바꿔도 다른 요일에 적은 글자는 그대로 둔다(저장은 전체 일괄, F05-11).
  Weekday? _selectedDay;

  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  /// dispose 에서는 `ref` 를 못 쓰므로 미리 잡아 둔다.
  late final UnsavedEdits _edits;

  @override
  void initState() {
    super.initState();
    _edits = ref.read(scheduleUnsavedEditsProvider);
    _slots = [
      for (final day in Weekday.values)
        for (final direction in RunDirection.values) _newSlot(day, direction),
    ];
  }

  _Slot _newSlot(Weekday day, RunDirection direction) {
    final entry = widget.entries
        .where((e) => e.weekday == day && e.direction == direction)
        .firstOrNull;
    return _Slot(
      weekday: day,
      direction: direction,
      address: entry?.address ?? '',
      detail: entry?.addressDetail ?? '',
      onChanged: _reportDirty,
    );
  }

  bool get _isDirty => _slots.any((slot) => slot.isDirty);

  /// 저장하지 않은 글자가 있는 요일 — 요일 알약의 점이 된다.
  Set<Weekday> get _dirtyDays => {
    for (final slot in _slots)
      if (slot.isDirty) slot.weekday,
  };

  /// 저장하지 않은 입력이 있는지 일정 화면에 알린다(뒤로가기 확인용) — 요일 알약의 점과 띠도 글자를 따라간다.
  void _reportDirty() {
    _edits.mark(this, dirty: _isDirty);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
    // 화면이 그려지는 도중에 구독자(일정 화면)를 흔들지 않도록 한 박자 뒤에 지운다.
    scheduleMicrotask(() => _edits.mark(this, dirty: false));
  }

  void _showError(String message) => setState(() {
    _bannerTone = AlertTone.missed;
    _banner = message;
  });

  /// 보낼 칸을 모은다 — 잘못된 입력이면 안내 문구를 돌려주고 `null` 목록을 준다.
  ({List<WeeklyAddressEntry>? entries, String? error}) _collect() {
    final entries = <WeeklyAddressEntry>[];
    for (final slot in _slots) {
      final address = slot.address.text.trim();
      final detail = slot.detail.text.trim();
      if (address.isEmpty) {
        // F05-11 — 한 칸만 비어도 서버가 전체(최대 14건)를 거절해
        // 다른 요일 수정분까지 잃는다. 보내기 전에 막는다.
        if (slot.isRegistered) {
          return (entries: null, error: '비어 있는 주소가 있습니다. 주소를 입력해 주세요');
        }
        if (detail.isNotEmpty) {
          return (
            entries: null,
            error:
                '${slot.weekday.longLabel} ${slot.direction.label}: '
                '주소를 먼저 입력해 주세요',
          );
        }
        continue;
      }
      entries.add(
        WeeklyAddressEntry(
          weekday: slot.weekday,
          direction: slot.direction,
          address: address,
          addressDetail: detail.isEmpty ? null : detail,
        ),
      );
    }
    if (entries.isEmpty) return (entries: null, error: '주소를 입력해 주세요');
    return (entries: entries, error: null);
  }

  Future<void> _save() async {
    if (_submitting) return;
    // 잠금(`_submitting`)은 이 검사 뒤에 건다 — 앞에서 걸면 경고 뒤 저장 버튼이 영구히 잠긴다(R46).
    final collected = _collect();
    final entries = collected.entries;
    if (entries == null) {
      _showError(collected.error ?? '주소를 입력해 주세요');
      return;
    }
    setState(() {
      _submitting = true;
      _banner = null;
    });

    try {
      await ref
          .read(weeklyAddressRepositoryProvider)
          .updateWeeklyAddress(widget.studentId, entries);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.boarded;
        _banner = '저장했어요';
      });
      // 저장한 글자가 새 기준이다 — 이후로는 고친 것이 없으므로 뒤로가기 확인이 뜨지 않는다.
      for (final slot in _slots) {
        slot.markSaved();
      }
      _reportDirty();
      ref.invalidate(weeklyAddressProvider(widget.studentId));
    } on Failure catch (failure) {
      if (!mounted) return;
      final failed = _failedEntriesOf(failure, entries);
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = switch (failure) {
          ApiFailure(code: 'ADDRESS_VERIFICATION_FAILED') =>
            failed.isEmpty
                ? '주소를 확인할 수 없습니다. 다시 입력해 주세요'
                : '${failed.map(_slotLabel).join(', ')}: '
                      '주소를 확인할 수 없습니다. 다시 입력해 주세요',
          _ => failureMessage(failure, fallback: '저장하지 못했습니다'),
        };
        // 실패한 첫 칸의 요일로 옮겨 가 바로 고칠 수 있게 한다.
        if (failed.isNotEmpty) _selectedDay = failed.first.weekday;
      });
    }
  }

  /// 서버가 `details.failed_entries`(검증에 실패한 주소 글자 목록, API_SPEC §3.7)로 돌려준 주소를
  /// 보낸 칸에 맞춰 본다 — 서버는 요일 · 방향 없이 주소 글자만 주므로 보낸 목록에서 같은 글자의 칸을 찾는다.
  List<WeeklyAddressEntry> _failedEntriesOf(
    Failure failure,
    List<WeeklyAddressEntry> sent,
  ) {
    if (failure is! ApiFailure) return const [];
    final raw = failure.details?['failed_entries'];
    if (raw is! List) return const [];
    final failedAddresses = raw.whereType<String>().toSet();
    return [
      for (final entry in sent)
        if (failedAddresses.contains(entry.address)) entry,
    ];
  }

  String _slotLabel(WeeklyAddressEntry entry) =>
      '${entry.weekday.longLabel} ${entry.direction.label}';

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay ?? _initialDay();
    final dirtyDays = _dirtyDays;
    final slotsOfDay = _slots.where((slot) => slot.weekday == selected);

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
                '매주 같은 요일에는 이 주소로 버스가 와요. 요일마다 등원 · 하원 주소를 따로 적을 수 있어요.',
                style: BaraedaTypography.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaSegmentedControl(
                block: true,
                options: [
                  for (final day in Weekday.values)
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
              for (final slot in slotsOfDay) ...[
                BaraedaInput(
                  // 고정 키 — 첫 글자를 치면 위에 "저장하지 않은 변경" 띠가 끼어드는데, 키가 없으면 입력칸이
                  // 새로 만들어져 포커스를 잃고 키보드가 닫힌다.
                  key: ValueKey('weekly-input-${slot.key}'),
                  label: '${selected.longLabel} · ${slot.direction.label}',
                  controller: slot.address,
                ),
                const SizedBox(height: BaraedaSpacing.space2),
                BaraedaInput(
                  key: ValueKey('weekly-detail-${slot.key}'),
                  label: '상세 주소 (동 · 출입구)',
                  controller: slot.detail,
                ),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              Text(
                '저장하면 주소를 확인한 뒤 노선에 반영해요. 이미 저장한 주소는 비울 수 없고 다른 주소로만 바꿀 수 있어요.',
                style: BaraedaTypography.bodySm.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaListGroup(
                children: [
                  BaraedaListRow(
                    leadingIcon: 'pencil',
                    title: '하루만 바꾸고 싶어요',
                    subtitle: '일일 변경을 쓰면 그날만 바뀌어요',
                    trailing: const BaraedaIcon('chevron-right'),
                    onTap: () => context.push(AppRoutes.dailyChange),
                  ),
                ],
              ),
              const SizedBox(height: BaraedaSpacing.space4),
            ],
          ),
        ),
        StickyActionBar(
          // 결과 안내는 고정 영역에 둔다 — 14칸이라 목록이 길어 스크롤 아래에 두면 저장 결과가 안 보인다.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_banner != null) ...[
                AlertBanner(tone: _bannerTone, body: _banner),
                const SizedBox(height: BaraedaSpacing.space2),
              ],
              BaraedaButton(
                label: '저장하기',
                block: true,
                onPressed: _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 처음 보여 줄 요일 — 주소가 있는 가장 이른 요일, 하나도 없으면 월요일.
  Weekday _initialDay() =>
      _slots
          .where((slot) => slot.isRegistered)
          .map((slot) => slot.weekday)
          .firstOrNull ??
      Weekday.mon;
}
