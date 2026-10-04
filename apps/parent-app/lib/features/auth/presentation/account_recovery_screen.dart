import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/ui/numbered_steps.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';

/// AUTH-08 · API_SPEC §2.9 — 아이디·비밀번호 복구. **비인증 진입점**(로그인
/// 화면에서만 들어온다, `router.dart` 의 `redirect` 가 로그인 전 화면으로
/// 허용).
///
/// **계정 존재 여부 노출 주의.** 서버는 번호의 가입 여부를 응답으로 구분하지
/// 않는다(§2.9 · Ruling 553) — 인증번호 요청은 미등록 번호도 `200` 이고 문자만
/// 나가지 않는다. 그래서 요청 뒤 안내는 **"가입된 번호라면 문자를 보냈다"** 로만
/// 말하고(번호가 없다고도, 보냈다고 단정하지도 않는다), 대조 실패는 이유를 가르지
/// 않는 `VERIFICATION_CODE_INVALID` 하나다.
///
/// **SMS 연동 전까지 서버가 `503 RECOVERY_UNAVAILABLE` 을 낸다**
/// (Ruling 329) — 문자 발송 수단이 없어 전화번호 인증이 성립하지 않는다.
/// 그동안의 복구는 관계자가 초기화하는 관리자 경유(§5.22)라 화면이
/// 처음부터 그 길을 안내한다.
class AccountRecoveryScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AccountRecoveryScreen> createState() =>
      _AccountRecoveryScreenState();
}

/// 503 응답을 받은 뒤 띠에 쓰는 문구(Ruling 329 · 829) — "문자로 찾기" 가 준비 중이라는 사실과 다음 행동.
const _unavailableNotice = '문자로 찾기는 준비 중이에요. 위 방법대로 다니는 학원에 요청해 주세요.';

/// 인증번호 자릿수 — 사양에 자릿수가 없어 시안의 6자리를 가정한다(`REPORT-MP §1.5`).
const _codeLength = 6;

class _AccountRecoveryScreenState extends ConsumerState<AccountRecoveryScreen> {
  final _phoneController = TextEditingController();

  String _type = 'login_id';

  /// "문자로 찾기" 줄을 눌러 입력 폼을 열었는가.
  bool _formOpen = false;
  bool _codeRequested = false;
  String _code = '';

  /// 서버가 `503 RECOVERY_UNAVAILABLE` 을 줬다 — 문자 발송 수단이 없어 해도 같은 결과라 줄을 꺼 둔다.
  bool _unavailable = false;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// 대조 실패는 이유를 가르지 않는 한 문구다(클래스 문서의 열거 위험 참고).
  String _messageFor(Failure failure) => switch (failure) {
    ApiFailure(
      code: 'VERIFICATION_CODE_INVALID',
    ) =>
      '휴대폰 번호 또는 인증번호를 확인할 수 없습니다',
    ApiFailure(code: 'RECOVERY_UNAVAILABLE') => _unavailableNotice,
    ApiFailure(code: 'VALIDATION_FAILED') => '입력값을 다시 확인해 주세요',
    ApiFailure(:final message) => message,
    NetworkFailure() => '네트워크 상태를 확인해 주세요',
    _ => '요청을 처리하지 못했습니다',
  };

  Future<void> _requestCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _banner = null;
    });

    try {
      await ref.read(authRepositoryProvider).recover(type: _type, phone: phone);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _codeRequested = true;
        _bannerTone = AlertTone.boarded;
        _banner = '가입된 번호라면 인증번호를 문자로 보냈어요. 받은 번호를 입력해 주세요.';
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      final unavailable =
          failure is ApiFailure && failure.code == 'RECOVERY_UNAVAILABLE';
      setState(() {
        _submitting = false;
        _bannerTone = unavailable ? AlertTone.info : AlertTone.missed;
        _banner = _messageFor(failure);
        if (unavailable) {
          _unavailable = true;
          _formOpen = false;
        }
      });
    }
  }

  Future<void> _verifyCode() async {
    final phone = _phoneController.text.trim();
    final code = _code.trim();
    if (code.length != _codeLength || _submitting) return;

    setState(() {
      _submitting = true;
      _banner = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .recover(type: _type, phone: phone, verificationCode: code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.boarded;
        _banner = _type == 'login_id'
            ? '문자로 아이디를 보내 드렸어요.'
            : '문자로 임시 비밀번호를 보내 드렸어요.';
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerTone = AlertTone.missed;
        _banner = _messageFor(failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: '아이디·비밀번호 찾기', onBack: () => context.pop()),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _codeRequested ? _codeStep() : _guideStep(),
                ),
              ),
            ),
            StickyActionBar(child: _bottomBar()),
          ],
        ),
      ),
    );
  }

  /// 처음 화면 — 학원에 요청하는 방법이 먼저, 문자로 찾기는 그 아래 한 줄(시안 `recovery`).
  /// 문자 발송 수단이 없는 동안 서버가 `503` 을 주므로(Ruling 329) 폼을 먼저 보여 주면 늘 실패한다.
  List<Widget> _guideStep() => [
    const AlertBanner(
      tone: AlertTone.info,
      title: '지금은 학원을 통해 찾아요',
      body: '전화번호로 찾기는 준비 중이에요.',
    ),
    const SizedBox(height: BaraedaSpacing.space4),
    const _AcademySteps(),
    const SizedBox(height: BaraedaSpacing.space3),
    _SmsRow(
      unavailable: _unavailable,
      open: _formOpen,
      onTap: () => setState(() => _formOpen = !_formOpen),
    ),
    if (_banner != null) ...[
      const SizedBox(height: BaraedaSpacing.space3),
      AlertBanner(tone: _bannerTone, body: _banner),
    ],
    if (_formOpen && !_unavailable) ...[
      const SizedBox(height: BaraedaSpacing.space4),
      ..._phoneForm(),
      const SizedBox(height: BaraedaSpacing.space4),
      // 버튼 비활성화만으로는 제출이 진행 중임이 드러나지 않는다 — password_change_screen.dart 와 같은 표시.
      if (_submitting) ...[
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: BaraedaSpacing.space4),
      ],
      BaraedaButton(
        label: '인증번호 받기',
        size: BaraedaButtonSize.lg,
        block: true,
        onPressed: _submitting ? null : _requestCode,
      ),
    ],
  ];

  /// 인증번호 입력 단계 — 안내 띠 + 찾을 항목 · 번호(잠금) + 6칸(시안 `recovery--code`).
  List<Widget> _codeStep() => [
    if (_banner != null) ...[
      AlertBanner(tone: _bannerTone, body: _banner),
      const SizedBox(height: BaraedaSpacing.space4),
    ],
    ..._phoneForm(),
    const SizedBox(height: BaraedaSpacing.space4),
    BaraedaCodeInput(
      label: '인증번호',
      value: _code,
      numeric: true,
      hint: '문자가 안 오면 1분 뒤에 다시 받을 수 있어요',
      onChanged: (value) => setState(() => _code = value),
    ),
    if (_submitting) ...[
      const SizedBox(height: BaraedaSpacing.space4),
      const Center(child: CircularProgressIndicator()),
    ],
  ];

  /// 찾을 항목 + 가입 시 등록한 휴대폰 번호 — 인증번호를 받은 뒤에는 바꿀 수 없다.
  List<Widget> _phoneForm() => [
    Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Text(
        '찾을 항목',
        style: BaraedaTypography.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: BaraedaFontWeight.bold,
        ),
      ),
    ),
    BaraedaSegmentedControl(
      options: const [
        BaraedaSegmentedOption('login_id', label: '아이디'),
        BaraedaSegmentedOption('password', label: '비밀번호'),
      ],
      value: _type,
      block: true,
      onChanged: _codeRequested
          ? null
          : (value) => setState(() => _type = value),
    ),
    const SizedBox(height: BaraedaSpacing.space4),
    BaraedaInput(
      label: '가입 시 등록한 휴대폰 번호',
      announceRequired: true,
      enabled: !_codeRequested,
      keyboardType: TextInputType.phone,
      controller: _phoneController,
    ),
  ];

  /// 맨 아래 고정 줄 — 처음에는 [로그인 화면으로], 인증번호 단계에서는 [확인하기](6자리를 채워야 켜진다).
  Widget _bottomBar() {
    if (!_codeRequested) {
      return BaraedaButton(
        label: '로그인 화면으로',
        size: BaraedaButtonSize.xl,
        block: true,
        onPressed: () => context.pop(),
      );
    }
    final complete = _code.length == _codeLength;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaButton(
          label: '확인하기',
          size: BaraedaButtonSize.xl,
          block: true,
          onPressed: complete && !_submitting ? _verifyCode : null,
        ),
        if (!complete) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          const WordWrapText(
            '인증번호 $_codeLength자리를 모두 입력해 주세요',
            textAlign: TextAlign.center,
            style: BaraedaTypography.bodySm,
          ),
        ],
      ],
    );
  }
}

/// "학원에 요청하는 방법" — 번호 매긴 3단계(연락 → 임시 비밀번호 → 로그인 뒤 변경).
class _AcademySteps extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const BaraedaCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('학원에 요청하는 방법', style: BaraedaTypography.h3),
          SizedBox(height: BaraedaSpacing.space3),
          NumberedSteps(
            steps: [
              (
                title: '다니는 학원에 연락해요',
                caption: '비밀번호 초기화를 요청하면 아이디도 알려 줘요',
              ),
              (title: '임시 비밀번호를 받아요', caption: '학원 관계자가 초기화해 줘요'),
              (
                title: '로그인하고 새 비밀번호로 바꿔요',
                caption: '바꾸기 전에는 다른 화면을 쓸 수 없어요',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "문자로 찾기" 줄 — 눌러서 폼을 연다. 서버가 503 을 준 뒤에는 `준비 중` 칩이 붙고 눌러도 반응이 없다.
class _SmsRow extends StatelessWidget {
  const new({
    required this.unavailable,
    required this.open,
    required this.onTap,
  });

  final bool unavailable;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const radius = BorderRadius.all(Radius.circular(BaraedaRadius.card));

    return BaraedaPressable(
      onTap: unavailable ? null : onTap,
      borderRadius: radius,
      semanticLabel: unavailable ? '문자로 찾기, 준비 중' : '문자로 찾기',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: radius,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
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
                      width: 40,
                      height: 40,
                      child: Center(
                        child: BaraedaIcon(
                          'message-square',
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '문자로 찾기',
                        style: BaraedaTypography.body.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      WordWrapText(
                        '휴대폰 번호로 인증번호를 받아요',
                        style: BaraedaTypography.caption.copyWith(
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space2),
                if (unavailable)
                  const BaraedaStatusPill(
                    status: BaraedaStatus.waiting,
                    label: '준비 중',
                  )
                else
                  BaraedaIcon(
                    open ? 'chevron-up' : 'chevron-down',
                    color: colors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
