import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 서버가 한 번에 주는 학원 검색 결과의 최대 건수(API_SPEC §2.1) — 이만큼 받았으면 더 있을 수 있다.
const _searchLimit = 20;

/// 학원 검색 + 결과 확인 + 선택 하나로 묶은 위젯(UF-X-01 학원 검색 단계).
///
/// 결과는 드롭다운이 아니라 **라디오 목록**이다(R48 시안 `signup--academy`) —
/// 학원명 · 지역 · 학원 코드가 한 번에 보이고 고른 줄이 눈에 띈다.
///
/// repository 를 직접 참조하지 않는다 — 검색 실행은 [onSearch] 콜백으로
/// 받는다. 화면(`SignupScreen`·`PendingApprovalScreen`)이
/// `authRepositoryProvider` 를 연결해 준다. 이렇게 하면 이 위젯 자체는 순수
/// `presentation` 이라 `domain`·`data` 어느 쪽도 몰라도 된다.
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
                label: '학원 검색',
                placeholder: '학원명 또는 학원 코드',
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
                label: '검색',
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
        // 서버는 최대 20건만 주고 잘렸다는 표시를 하지 않는다(API_SPEC §2.1) — 가득 찼으면 좁히라고 알린다.
        if (_results.length >= _searchLimit)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space2),
            child: WordWrapText(
              '결과가 많아 일부만 보여요. 검색어를 더 자세히 입력해 주세요',
              style: BaraedaTypography.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space3),
            child: Semantics(
              label: '검색한 학원',
              container: true,
              child: _AcademyRadioList(
                academies: _results,
                selectedId: widget.selected?.id,
                onSelected: widget.onSelected,
              ),
            ),
          ),
      ],
    );
  }
}

/// 검색 결과 라디오 목록 — 한 카드 안에 줄마다 `학원명` + `지역 · 학원 코드`.
class _AcademyRadioList extends StatelessWidget {
  const new({
    required this.academies,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AcademySummary> academies;
  final String? selectedId;
  final ValueChanged<AcademySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const radius = BorderRadius.all(Radius.circular(BaraedaRadius.card));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: radius,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          children: [
            for (var i = 0; i < academies.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: _AcademyRow(
                  academy: academies[i],
                  selected: academies[i].id == selectedId,
                  onTap: () => onSelected(academies[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AcademyRow extends StatelessWidget {
  const new({
    required this.academy,
    required this.selected,
    required this.onTap,
  });

  final AcademySummary academy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = '${academy.region} · 학원 코드 ${academy.code}';

    return BaraedaPressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      selected: selected,
      semanticLabel: '${academy.name}, $caption',
      child: ColoredBox(
        color: selected ? colors.accentPrimarySoft : colors.surfaceCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space3,
              vertical: BaraedaSpacing.space2,
            ),
            child: Row(
              children: [
                _RadioMark(selected: selected),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WordWrapText(
                        academy.name,
                        style: BaraedaTypography.body.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      WordWrapText(
                        caption,
                        style: BaraedaTypography.caption.copyWith(
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 둥근 라디오 표시 — 고른 줄은 가운데에 점이 찬다(색만으로 구분하지 않는다).
class _RadioMark extends StatelessWidget {
  const new({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderControl,
            width: 2,
          ),
        ),
        child: SizedBox(
          width: 24,
          height: 24,
          child: selected
              ? Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentPrimary,
                    ),
                    child: const SizedBox(width: 12, height: 12),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
