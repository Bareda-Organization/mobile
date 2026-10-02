import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/core/ui/minute_ticker.dart';

/// 자녀 연결 (FEATURE_SPEC §5.1 색인 기준 P-02, BRIEF 표기 "P-01" 은
/// 정본과 어긋남 — 보고서 §2 참고) · 학생 코드 생성(S-05) 화면.
///
/// 학부모·학생이 같은 화면을 쓰되 [roleCapabilitiesProvider] 로 흐름을
/// 가른다(§1.1 "역할 분기는 role_policy 한 곳" — 이 파일에 역할 문자열을
/// 직접 쓰지 않는다).
///
/// **Ruling 324** — 가입 승인과 자녀 연결을 분리하며 요청(§3.2) 단계를
/// 없앴다. 학생이 선행 조건 없이 언제든 코드를 만들고(§3.3), 학부모는 그
/// 코드를 입력하기만 한다(§3.4) — 2단계로 줄었다.
class ChildLinkScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

class _ChildLinkScreenState extends ConsumerState<ChildLinkScreen> {
  String _code = '';

  bool _submitting = false;
  String? _formError;
  String? _successMessage;
  DateTime? _generatedCodeExpiresAt;

  /// P2 — 지금 `_formError` 가 `LINK_CODE_INVALID` 로 실패한 것인가.
  /// 서버는 코드 오류·시도 상한 초과·중복 코드를 전부 이 코드 하나로
  /// 합쳐 돌려준다(코드 실재 노출 방지, `§3.4`) — 응답을 갈라 안내하지
  /// 못하므로 이 코드일 때는 항상 시도 상한 고정 안내를 함께 보여준다.
  bool _formErrorIsCodeInvalid = false;

  Future<void> _submitConfirmLink() async {
    if (_code.length != 6 || _submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _formErrorIsCodeInvalid = false;
      _successMessage = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.confirmLink(_code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _successMessage = '${result.name} 자녀 연결이 완료됐습니다.';
      });
      // 홈 화면의 자녀 목록이 낡지 않도록 무효화한다(C-10 계열 — 다시
      // 조회해 서버 상태를 그대로 반영).
      ref.invalidate(myStudentsProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
        _formErrorIsCodeInvalid =
            failure is ApiFailure && failure.code == 'LINK_CODE_INVALID';
      });
    }
  }

  Future<void> _submitGenerateCode() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _formErrorIsCodeInvalid = false;
      _successMessage = null;
    });

    final repository = ref.read(linkRepositoryProvider);
    try {
      final result = await repository.generateLinkCode();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _code = result.code;
        _generatedCodeExpiresAt = result.expiresAt;
        _successMessage = '이 코드는 1회만 쓸 수 있습니다. 학부모 앱에 알려 주세요.';
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = _messageFor(failure);
      });
    }
  }

  /// 클립보드에 복사하고 결과를 알린다 — 복사 성공은 되돌릴 수 없는 동작이 아니라 한 줄 안내로 충분하다.
  Future<void> _copy(String text, String doneMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: WordWrapText(doneMessage)));
  }

  /// 학부모에게 메신저로 붙여 넣을 문장 — 코드만 보내면 어디에 입력하는지 모른다.
  String _shareMessage(String code, DateTime expiresAt) =>
      '바래다 자녀 연결 코드 $code · 학부모 앱의 [자녀 연결] 에서 입력해 주세요 · '
      '${DateFormat('H:mm').format(expiresAt.toLocal())} 까지 쓸 수 있습니다';

  String _messageFor(Failure failure) => switch (failure) {
    ApiFailure(code: 'ALREADY_LINKED') => '이미 연결된 자녀입니다',
    ApiFailure(code: 'LINK_CODE_INVALID') => '코드가 올바르지 않거나 만료됐습니다',
    ApiFailure(:final message) => message,
    NetworkFailure() => '네트워크 상태를 확인해 주세요',
    _ => '요청을 처리하지 못했습니다',
  };

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    // 학생만 코드 생성 진입점을 갖는다(role_policy.dart) — 그 외(학부모 ·
    // 아직 role 미확정)는 코드 입력 흐름을 보여준다.
    final isStudent = capabilities?.canGenerateLinkCode ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '자녀 연결'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isStudent ? _buildStudentFlow() : _buildParentFlow(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParentFlow() {
    return [
      const Text('자녀가 발급받은 코드 입력', style: BaraedaTypography.h3),
      const SizedBox(height: BaraedaSpacing.space4),
      const WordWrapText('자녀 앱에서 만든 연결 코드를 입력해 주세요.'),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaCodeInput(
        value: _code,
        onChanged: (value) => setState(() => _code = value),
      ),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaButton(
        label: '연결 완료하기',
        size: BaraedaButtonSize.lg,
        onPressed: (_submitting || _code.length != 6)
            ? null
            : _submitConfirmLink,
      ),
      ..._buildMessages(),
    ];
  }

  List<Widget> _buildStudentFlow() {
    return [
      const Text('학부모 연결 코드 생성', style: BaraedaTypography.h3),
      const SizedBox(height: BaraedaSpacing.space4),
      const WordWrapText(
        '코드는 1회만 쓸 수 있고 발급 후 일정 시간이 지나면 만료됩니다. '
        '다시 만들면 이전 코드는 더 이상 쓸 수 없습니다.',
      ),
      const SizedBox(height: BaraedaSpacing.space4),
      BaraedaButton(
        label: '코드 생성하기',
        size: BaraedaButtonSize.lg,
        onPressed: _submitting ? null : _submitGenerateCode,
      ),
      if (_code.isNotEmpty) ...[
        const SizedBox(height: BaraedaSpacing.space6),
        Center(
          child: Text(
            _code,
            style: BaraedaTypography.h1.copyWith(letterSpacing: 8),
          ),
        ),
        if (_generatedCodeExpiresAt case final expiresAt?) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          Center(child: Text('만료 시각: ${formatDateTime(expiresAt)}')),
          Center(child: _RemainingTime(expiresAt: expiresAt)),
          const SizedBox(height: BaraedaSpacing.space4),
          MinuteTicker(
            builder: (context, now) {
              final isExpired = !expiresAt.isAfter(now);
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: BaraedaSpacing.space2,
                children: [
                  BaraedaButton(
                    label: '코드 복사',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: isExpired
                        ? null
                        : () => _copy(_code, '코드를 복사했습니다'),
                  ),
                  BaraedaButton(
                    label: '안내 문구 복사',
                    size: BaraedaButtonSize.sm,
                    variant: BaraedaButtonVariant.secondary,
                    onPressed: isExpired
                        ? null
                        : () => _copy(
                            _shareMessage(_code, expiresAt),
                            '안내 문구를 복사했습니다',
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
      ..._buildMessages(),
    ];
  }

  List<Widget> _buildMessages() {
    return [
      if (_formError != null) ...[
        const SizedBox(height: BaraedaSpacing.space4),
        AlertBanner(tone: AlertTone.missed, body: _formError),
        if (_formErrorIsCodeInvalid) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          const WordWrapText(
            '여러 번 틀리면 10분 동안 입력이 막힙니다 · 계속 안 되면 자녀 앱에서 코드를 다시 발급',
            style: BaraedaTypography.bodySm,
          ),
        ],
      ],
      if (_successMessage != null) ...[
        const SizedBox(height: BaraedaSpacing.space4),
        AlertBanner(tone: AlertTone.boarded, body: _successMessage),
      ],
    ];
  }
}

/// 코드 만료까지 남은 시간 — 1분마다 줄고, 만료되면 새로 만들라고 알린다(코드는 1회용이라 만료 뒤에는 쓸 수 없다).
class _RemainingTime extends StatelessWidget {
  const new({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    return MinuteTicker(
      builder: (context, now) {
        final left = expiresAt.difference(now);
        return WordWrapText(
          left <= Duration.zero
              ? '코드가 만료됐습니다 · 새 코드를 만들어 주세요'
              : '남은 시간 ${formatRemaining(left)}',
          style: BaraedaTypography.bodySm,
        );
      },
    );
  }
}
