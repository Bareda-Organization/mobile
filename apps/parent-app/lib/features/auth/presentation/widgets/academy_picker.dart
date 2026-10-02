import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 학원 검색 + 결과 확인 + 선택 하나로 묶은 위젯(UF-X-01 학원 검색 단계).
/// `AcademySummary.displayLabel` 이 이미 `{name}·{region}·{code}` 형식을
/// 만들어 주므로 이 위젯은 검색·목록·선택만 담당한다.
///
/// repository 를 직접 참조하지 않는다 — 검색 실행은 [onSearch] 콜백으로
/// 받는다. 화면(`SignupScreen`·`PendingApprovalScreen`)이 `authRepositoryProvider`
/// 를 연결해 준다. 이렇게 하면 이 위젯 자체는 순수 `presentation` 이라
/// `domain`·`data` 어느 쪽도 몰라도 된다.
class AcademyPicker extends StatefulWidget {
  /// [onSearch] 는 검색어를 받아 결과를 돌려주는 콜백, 실패하면 [Failure] 를
  /// 던진다. [onSelected] 는 사용자가 결과 하나를 고르면 불린다.
  const new({
    required this.onSearch,
    required this.onSelected,
    super.key,
    this.selected,
  });

  final Future<List<AcademySummary>> Function(String query) onSearch;
  final ValueChanged<AcademySummary> onSelected;
  final AcademySummary? selected;

  @override
  State<AcademyPicker> createState() => _AcademyPickerState();
}

class _AcademyPickerState extends State<AcademyPicker> {
  final _queryController = TextEditingController();
  List<AcademySummary> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.onSearch(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
        _loading = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (failure) {
          ApiFailure(:final message) => message,
          NetworkFailure() => '네트워크 상태를 확인해 주세요',
          _ => '학원 검색에 실패했습니다',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BaraedaInput(
                label: '학원',
                hint: '학원명 또는 학원 코드로 검색',
                required: true,
                controller: _queryController,
                onChanged: (_) {
                  if (_searched) setState(() => _searched = false);
                },
              ),
            ),
            const SizedBox(width: BaraedaSpacing.space2),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: BaraedaButton(
                label: '검색하기',
                variant: BaraedaButtonVariant.secondary,
                onPressed: _loading ? null : _search,
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space2),
            child: WordWrapText(
              _error!,
              style: BaraedaTypography.caption.copyWith(
                color: context.colors.statusMissed,
              ),
            ),
          ),
        if (_searched && _results.isEmpty && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space2),
            child: WordWrapText(
              '학원을 찾을 수 없습니다 — 학원에 문의해 주세요',
              style: BaraedaTypography.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space2),
            child: BaraedaSelect(
              options: [
                for (final academy in _results)
                  BaraedaSelectOption(academy.id, label: academy.displayLabel),
              ],
              value: widget.selected?.id,
              onChanged: (value) {
                if (value == null) return;
                final academy = _results.firstWhere((a) => a.id == value);
                widget.onSelected(academy);
              },
            ),
          ),
      ],
    );
  }
}
