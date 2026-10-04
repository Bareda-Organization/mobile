import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/ui/numbered_steps.dart';

/// 서버가 코드 오류 · 시도 상한 초과 · 중복 코드를 `LINK_CODE_INVALID` 하나로 합쳐 돌려주므로(코드 실재 노출 방지,
/// `§3.4`) 이 코드일 때는 항상 시도 상한 고정 안내를 함께 보여 준다.
const linkCodeInvalidTitle = '코드가 올바르지 않거나 만료됐어요';
const linkCodeInvalidNotice =
    '여러 번 틀리면 10분 동안 입력이 막혀요. '
    '계속 안 되면 자녀 앱에서 코드를 다시 만들어요.';

/// 학부모 — 자녀가 만든 코드를 입력하는 화면(시안 `child-link` · `child-link--error`).
///
/// 연결 순서 3단계를 먼저 보여 주고 아래에 6칸 입력을 둔다. 주 단추는 화면 맨 아래에 고정이라 이 위젯 밖에 있다.
class ParentLinkView extends StatelessWidget {
  const new({
    required this.code,
    required this.onCodeChanged,
    required this.invalid,
    required this.error,
    super.key,
  });

  final String code;
  final ValueChanged<String> onCodeChanged;

  /// 이번 입력이 `LINK_CODE_INVALID` 로 거절됐다 — 칸이 빨개지고 안내 띠에 시도 상한 안내가 붙는다.
  final bool invalid;

  /// 거절 문구(서버 코드별) — 없으면 띠를 그리지 않는다.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final message = error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('자녀가 만든 코드를 입력해요', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space3),
        const BaraedaCard(
          child: NumberedSteps(
            steps: [
              (title: '자녀 앱을 열어요', caption: '설정 › 부모님과 연결하기 › 코드 만들기'),
              (title: '만들어진 코드 6자리를 받아요', caption: '메신저로 보내 달라고 해도 돼요'),
              (title: '아래에 입력해요', caption: null),
            ],
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaCodeInput(
          label: '연결 코드 6자리',
          value: code,
          invalid: invalid,
          onChanged: onCodeChanged,
        ),
        if (message != null) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          if (invalid)
            const AlertBanner(
              tone: AlertTone.missed,
              title: linkCodeInvalidTitle,
              body: linkCodeInvalidNotice,
            )
          else
            AlertBanner(tone: AlertTone.missed, body: message),
        ],
      ],
    );
  }
}
