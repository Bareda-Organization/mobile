import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/core/ui/word_span.dart';

/// 학생 — 부모님과 연결할 코드를 만드는 화면의 본문(시안 `link-code*`). 세 모양이다.
///
/// - 처음([code] 없음): 코드 없이 안내만. 들어오자마자 자동으로 만들면 부모에게 이미 준 코드가 무효가 되므로
///   첫 상태를 따로 둔다.
/// - 살아 있는 코드: 큰 6칸 + 만료 시각 · 남은 시간 + 부모님께 보낼 문구.
/// - 만료된 코드: 띠 + 취소선 칸 + 지금은 쓸 수 없다는 문구. 복사 단추는 꺼진다.
///
/// 주 단추는 화면 맨 아래에 고정이라 이 위젯 밖에 있다.
class StudentCodeView extends StatelessWidget {
  const new({
    required this.code,
    required this.expiresAt,
    required this.now,
    required this.shareMessage,
    required this.onCopyCode,
    required this.error,
    super.key,
  });

  /// 만든 코드. 아직 안 만들었으면 `null`.
  final String? code;
  final DateTime? expiresAt;
  final DateTime now;

  /// 부모님께 메신저로 붙여 넣을 문장 — 코드만 보내면 어디에 입력하는지 모른다.
  final String? shareMessage;
  final VoidCallback onCopyCode;
  final String? error;

  /// 이 코드가 만료됐는가 — 만료 시각이 지금과 같거나 이전이다.
  static bool isExpired(DateTime expiresAt, DateTime now) =>
      !expiresAt.isAfter(now);

  @override
  Widget build(BuildContext context) {
    final issued = code;
    final expires = expiresAt;
    final message = error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issued == null || expires == null)
          const _Intro()
        else
          _Issued(
            code: issued,
            expiresAt: expires,
            expired: isExpired(expires, now),
            remaining: expires.difference(now),
            shareMessage: shareMessage,
            onCopyCode: onCopyCode,
          ),
        if (message != null) ...[
          const SizedBox(height: BaraedaSpacing.space4),
          AlertBanner(tone: AlertTone.missed, body: message),
        ],
      ],
    );
  }
}

/// 처음 화면 — 연결 아이콘 + 한 줄 설명 + 알아 둘 것 셋.
class _Intro extends StatelessWidget {
  const new();

  static const _notes = [
    ('check', '코드는 한 번만 쓸 수 있어요'),
    ('clock', '만든 뒤 일정 시간이 지나면 만료돼요'),
    ('refresh', '새로 만들면 이전 코드는 쓸 수 없어요'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BaraedaSpacing.space6),
        Center(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.statusIdleSoft,
              ),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: BaraedaIcon(
                    'link',
                    size: 28,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        const Text(
          '부모님과 연결할 코드를 만들어요',
          textAlign: TextAlign.center,
          style: BaraedaTypography.h3,
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        WordWrapText(
          '6자리 코드를 만들어 부모님께 알려 주면 부모님 앱에서 내 버스를 볼 수 있어요.',
          textAlign: TextAlign.center,
          style: BaraedaTypography.body.copyWith(
            color: colors.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(BaraedaRadius.card),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _notes.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                _NoteRow(icon: _notes[i].$1, text: _notes[i].$2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const new({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaraedaSpacing.space3,
          vertical: BaraedaSpacing.space2,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(BaraedaRadius.sm),
                  color: colors.statusIdleSoft,
                ),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(child: BaraedaIcon(icon)),
                ),
              ),
            ),
            const SizedBox(width: BaraedaSpacing.space3),
            Expanded(child: WordWrapText(text, style: BaraedaTypography.body)),
          ],
        ),
      ),
    );
  }
}

/// 만든 코드 — 살아 있으면 큰 6칸 + 복사, 만료되면 띠 + 취소선 + 꺼진 복사.
class _Issued extends StatelessWidget {
  const new({
    required this.code,
    required this.expiresAt,
    required this.expired,
    required this.remaining,
    required this.shareMessage,
    required this.onCopyCode,
  });

  final String code;
  final DateTime expiresAt;
  final bool expired;
  final Duration remaining;
  final String? shareMessage;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final share = shareMessage;
    final until = formatClock(expiresAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('부모님께 알려 줄 코드예요', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space3),
        if (expired)
          const AlertBanner(
            tone: AlertTone.moving,
            title: '코드가 만료됐어요',
            body: '새 코드를 만들어 주세요.',
          )
        else
          Text.rich(
            TextSpan(
              children: [
                wordSpan('코드는 ', style: _bodyStyle(colors)),
                wordSpan(
                  '한 번만',
                  style: _bodyStyle(colors).copyWith(
                    color: colors.textPrimary,
                    fontWeight: BaraedaFontWeight.bold,
                  ),
                ),
                wordSpan(
                  ' 쓸 수 있어요. 새로 만들면 이전 코드는 쓸 수 없어요.',
                  style: _bodyStyle(colors),
                ),
              ],
            ),
          ),
        const SizedBox(height: BaraedaSpacing.space3),
        BaraedaCard(
          highlight: !expired,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BaraedaCodeDisplay(code: code, expired: expired),
              const SizedBox(height: BaraedaSpacing.space3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BaraedaIcon('clock', size: 16, color: colors.textSecondary),
                  const SizedBox(width: BaraedaSpacing.space2),
                  Flexible(
                    child: WordWrapText(
                      expired
                          ? '만료 시각 $until · 지금은 쓸 수 없어요'
                          : '만료 시각 $until · '
                                '남은 시간 ${formatRemaining(remaining)}',
                      style: BaraedaTypography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: BaraedaSpacing.space3),
        if (expired)
          // 만료된 코드는 어느 복사도 못 한다 — 꺼진 채 둘 다 보여 "왜 안 눌리는지" 가 코드 모양에서 읽힌다.
          const Row(
            children: [
              Expanded(
                child: BaraedaButton(
                  label: '코드만 복사',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                ),
              ),
              SizedBox(width: BaraedaSpacing.space2),
              Expanded(
                child: BaraedaButton(
                  label: '안내 문구 복사',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                ),
              ),
            ],
          )
        else
          BaraedaButton(
            label: '코드만 복사',
            variant: BaraedaButtonVariant.secondary,
            block: true,
            onPressed: onCopyCode,
          ),
        if (share != null) ...[
          const SizedBox(height: BaraedaSpacing.space4),
          Text(
            '부모님께 보낼 문구',
            style: BaraedaTypography.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: BaraedaFontWeight.bold,
            ),
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(BaraedaRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.space3),
              child: WordWrapText(
                share,
                style: BaraedaTypography.bodySm.copyWith(
                  color: expired ? colors.textTertiary : colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  TextStyle _bodyStyle(BaraedaColors colors) =>
      BaraedaTypography.body.copyWith(color: colors.textSecondary, height: 1.6);
}
