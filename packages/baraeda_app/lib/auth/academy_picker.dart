import 'package:baraeda_app/auth/academy_radio_list.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 학원 검색 API 의 쪽 크기 — 서버 기본값이다(API_SPEC §2.1). 결과가 이만큼 꽉 차면 더 있을 수 있다.
const academySearchPageSize = 20;

/// 검색 결과를 보이는 모양과 그 모양에 붙는 문구 — 두 앱의 가입 화면이 각자 쓴다.
enum AcademyPickerStyle {
  /// 학원명 · 지역 · 학원 코드가 한 번에 보이는 라디오 목록(학부모 · 학생 앱).
  radioList(
    inputLabel: '학원 검색',
    placeholder: '학원명 또는 학원 코드',
    searchLabel: '검색',
    tooManyNotice: '결과가 많아 일부만 보여요. 검색어를 더 자세히 입력해 주세요',
  ),

  /// 한 줄 드롭다운(버스기사 · 동승자 앱).
  dropdown(
    inputLabel: '학원',
    placeholder: '학원명 또는 학원 코드로 검색',
    searchLabel: '검색하기',
    tooManyNotice: '검색 결과가 많아요. 학원 이름을 더 자세히 입력해 주세요',
  );

  new({
    required this.inputLabel,
    required this.placeholder,
    required this.searchLabel,
    required this.tooManyNotice,
  });

  /// 검색어 입력칸 이름.
  final String inputLabel;

  /// 검색어 입력칸 안내.
  final String placeholder;

  /// 검색 단추 이름.
  final String searchLabel;

  /// 결과가 쪽 크기에 닿았을 때 좁히라는 안내.
  final String tooManyNotice;
}

/// 학원 검색 + 결과 확인 + 선택 하나로 묶은 위젯(UF-X-01 학원 검색 단계).
///
/// repository 를 직접 참조하지 않는다 — 검색 실행은 [onSearch] 콜백으로 받는다. 화면(`SignupScreen` ·
/// `PendingApprovalScreen`)이 `authRepositoryProvider` 를 연결해 준다.
class AcademyPicker extends StatefulWidget {
  /// [onSearch] 는 검색어를 받아 결과를 돌려주는 콜백, 실패하면 [Failure] 를 던진다. [onSelected] 는
  /// 사용자가 결과 하나를 고르면 불린다. [style] 이 결과 모양과 문구를 정한다.
  const new({
    required this.style,
    required this.onSearch,
    required this.onSelected,
    super.key,
    this.selected,
  });

  /// 결과를 보이는 모양과 문구.
  final AcademyPickerStyle style;

  /// 검색어로 학원을 찾는다.
  final Future<List<AcademySummary>> Function(String query) onSearch;

  /// 결과 하나를 고르면 불린다.
  final ValueChanged<AcademySummary> onSelected;

  /// 지금 고른 학원 — 없으면 `null`.
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
          _ => '학원 검색에 실패했어요',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final colors = context.colors;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BaraedaInput(
                label: style.inputLabel,
                placeholder: style.placeholder,
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
                label: style.searchLabel,
                variant: BaraedaButtonVariant.secondary,
                onPressed: _loading ? null : _search,
              ),
            ),
          ],
        ),
        if (error != null) _Notice(error, color: colors.statusMissed),
        if (_searched && _results.isEmpty && error == null)
          _Notice('학원을 찾을 수 없어요 — 학원에 문의해 주세요', color: colors.textSecondary),
        // 서버는 최대 20건만 주고 잘렸다는 표시를 하지 않는다(API_SPEC §2.1) — 가득 찼으면 좁히라고 알린다.
        if (_results.length >= academySearchPageSize)
          _Notice(style.tooManyNotice, color: colors.textSecondary),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space3),
            child: switch (style) {
              AcademyPickerStyle.radioList => Semantics(
                label: '검색한 학원',
                container: true,
                child: AcademyRadioList(
                  academies: _results,
                  selectedId: widget.selected?.id,
                  onSelected: widget.onSelected,
                ),
              ),
              AcademyPickerStyle.dropdown => BaraedaSelect(
                options: [
                  for (final academy in _results)
                    BaraedaSelectOption(
                      academy.id,
                      label: academy.displayLabel,
                    ),
                ],
                value: widget.selected?.id,
                onChanged: (value) {
                  if (value == null) return;
                  widget.onSelected(_results.firstWhere((a) => a.id == value));
                },
              ),
            },
          ),
      ],
    );
  }
}

/// 입력칸 아래 한 줄 안내(오류 · 결과 없음 · 좁히기).
class _Notice extends StatelessWidget {
  const new(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: BaraedaSpacing.space2),
    child: WordWrapText(
      text,
      style: BaraedaTypography.caption.copyWith(color: color),
    ),
  );
}
