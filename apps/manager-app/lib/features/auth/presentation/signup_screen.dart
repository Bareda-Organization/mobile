import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';

/// UF-X-01 — 회원가입: 아이디·비밀번호·이름·연락처 → 역할 선택(버스기사·동승자) →
/// 학원 검색·선택 → `POST /auth/signup` → `pending`.
///
/// 가입 응답에는 토큰이 없지만 `pending` 계정도 로그인은 성공하므로(§2.5) 방금 입력한 아이디·비밀번호로
/// 자동 로그인해 승인 대기 화면으로 간다(UF-X-01, `Ruling 861`). 자동 로그인이 실패하면 로그인 화면으로
/// 돌려보내고 가입 접수 안내만 보인다.
/// `parent_app` 의 같은 화면과 구조가 같고, 역할 선택지만 이 앱이 담당하는
/// 2종(`role_policy.dart` 의 "버스기사(`driver`)"·"동승자(`escort`)")으로
/// 바뀐다(§1.1).
class SignupScreen extends ConsumerStatefulWidget {
  /// 이 앱 라우트(`/signup`)로만 진입한다.
  const new({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _role = 'driver';
  AcademySummary? _academy;
  bool _submitting = false;
  String? _loginIdError;
  String? _formError;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// 아직 비어 있는 항목 이름(화면 순서) — 단추 아래에 그대로 적는다.
  List<String> get _missing => [
    if (_loginIdController.text.trim().isEmpty) '아이디',
    if (_passwordController.text.isEmpty) '비밀번호',
    if (_nameController.text.trim().isEmpty) '이름',
    if (_phoneController.text.trim().isEmpty) '연락처',
    if (_academy == null) '학원',
  ];

  /// 서버가 `422` 로 거절할 길이를 넘었는가(아이디 50자 · 비밀번호 72바이트).
  bool get _tooLong =>
      loginIdLengthError(_loginIdController.text) != null ||
      passwordLengthError(_passwordController.text) != null;

  bool get _canSubmit => !_submitting && _missing.isEmpty && !_tooLong;

  /// 꺼진 단추 아래 이유 — 켜져 있으면 `null`.
  String? get _disabledReason {
    final missing = _missing;
    if (missing.isNotEmpty) return '아직 채우지 않은 항목 · ${missing.join(' · ')}';
    if (isPasswordTooShort(_passwordController.text)) {
      return passwordTooShortMessage;
    }
    if (_tooLong) return '길이를 넘은 항목을 줄이면 눌러요';
    return null;
  }

  Future<void> _submit() async {
    final academy = _academy;
    if (!_canSubmit || academy == null) return;

    setState(() {
      _submitting = true;
      _loginIdError = null;
      _formError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      await repository.signup(
        SignupRequest(
          role: _role,
          loginId: _loginIdController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          academyId: academy.id,
        ),
      );
      if (!mounted) return;
      // 서버가 201 을 확정한 뒤에만 다음으로 간다 — 낙관적 UI 금지.
      await _signInAfterSignup(repository);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (failure) {
          case ApiFailure(code: 'DUPLICATE_LOGIN_ID'):
            _loginIdError = '이미 사용 중인 아이디예요';
          case ApiFailure(code: 'ACADEMY_NOT_FOUND'):
            _formError = '학원을 찾을 수 없어요 — 학원에 문의해 주세요';
          case ApiFailure(:final message):
            _formError = message;
          case NetworkFailure():
            _formError = '네트워크 상태를 확인해 주세요';
          default:
            _formError = '가입 신청에 실패했어요';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = '가입 신청에 실패했어요';
      });
    }
  }

  /// 가입 직후 자동 로그인(UF-X-01, `Ruling 861` ⑥) — 성공하면 역할·상태만 채우고 화면 전환은 라우터에 맡긴다
  /// (`LoginScreen` 과 같은 방식 — 승인 대기 화면으로 간다). 실패하면 가입은 이미 접수됐으니 로그인 화면으로
  /// 돌려보내 직접 로그인하게 한다.
  Future<void> _signInAfterSignup(AuthRepository repository) async {
    try {
      final response = await repository.login(
        loginId: _loginIdController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      applyLoginResponse(ref, response);
    } on Object {
      // 가입은 접수됐다 — 로그인 쪽 실패 종류와 상관없이 "가입 실패" 로 보이면 안 된다.
      _goToLoginAfterSignup();
    }
  }

  void _goToLoginAfterSignup() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: WordWrapText('가입 신청이 접수되었어요. 로그인 후 진행 상황을 볼 수 있어요.'),
      ),
    );
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    final academy = _academy;
    final reason = _disabledReason;

    return Scaffold(
      appBar: const ManagerHeader(title: '회원가입', showSos: false),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoleSection(
                    role: _role,
                    onChanged: (value) => setState(() => _role = value),
                  ),
                  const SizedBox(height: BaraedaSpacing.space4),
                  _AccountFields(
                    loginIdController: _loginIdController,
                    passwordController: _passwordController,
                    nameController: _nameController,
                    phoneController: _phoneController,
                    loginIdError: _loginIdError,
                    onLoginIdChanged: () {
                      if (_loginIdError != null) {
                        setState(() => _loginIdError = null);
                      }
                      setState(() {});
                    },
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: BaraedaSpacing.space4),
                  if (academy == null)
                    AcademyPicker(
                      style: AcademyPickerStyle.dropdown,
                      onSearch: repository.searchAcademies,
                      selected: academy,
                      onSelected: (picked) => setState(() => _academy = picked),
                    )
                  else
                    _SelectedAcademyCard(
                      academy: academy,
                      onChange: () => setState(() => _academy = null),
                    ),
                  if (_formError != null) ...[
                    const SizedBox(height: BaraedaSpacing.space4),
                    AlertBanner(tone: AlertTone.missed, body: _formError),
                  ],
                ],
              ),
            ),
          ),
          _SignupActionBar(
            onSubmit: _canSubmit ? _submit : null,
            disabledReason: _submitting ? null : reason,
            showGuide: reason == null && !_submitting,
          ),
        ],
      ),
    );
  }
}

/// 역할 선택(버스기사 · 동승자) 과 역할별 한 줄 설명.
class _RoleSection extends StatelessWidget {
  const new({required this.role, required this.onChanged});

  final String role;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '역할',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaSegmentedControl(
          options: const [
            BaraedaSegmentedOption('driver', label: '버스기사'),
            BaraedaSegmentedOption('escort', label: '동승자'),
          ],
          value: role,
          block: true,
          onChanged: onChanged,
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        WordWrapText(
          '버스기사 — 운행 시작 · 승하차지 도착 처리. 동승자 — 학생 승차 · 하차 처리.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 아이디 · 비밀번호 · 이름 · 연락처 입력 4칸.
class _AccountFields extends StatelessWidget {
  const new({
    required this.loginIdController,
    required this.passwordController,
    required this.nameController,
    required this.phoneController,
    required this.loginIdError,
    required this.onLoginIdChanged,
    required this.onChanged,
  });

  final TextEditingController loginIdController;
  final TextEditingController passwordController;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final String? loginIdError;
  final VoidCallback onLoginIdChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaInput(
          label: '아이디',
          hint: '50자 이하',
          kind: BaraedaInputKind.username,
          controller: loginIdController,
          error: loginIdError ?? loginIdLengthError(loginIdController.text),
          onChanged: (_) => onLoginIdChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '비밀번호',
          hint: '영문 72자 · 한글 24자까지',
          obscureText: true,
          kind: BaraedaInputKind.newPassword,
          controller: passwordController,
          error: passwordLengthError(passwordController.text),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '이름',
          controller: nameController,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '연락처',
          kind: BaraedaInputKind.phone,
          controller: phoneController,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

/// 하단 고정 `가입 신청하기` 단추와 승인 안내 문구.
class _SignupActionBar extends StatelessWidget {
  const new({
    required this.onSubmit,
    required this.disabledReason,
    required this.showGuide,
  });

  final VoidCallback? onSubmit;
  final String? disabledReason;
  final bool showGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BottomActionBar(
      children: [
        BaraedaButton(
          label: '가입 신청하기',
          size: BaraedaButtonSize.xl,
          block: true,
          onPressed: onSubmit,
          disabledReason: disabledReason,
        ),
        if (showGuide) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          Text(
            '신청하면 학원 관계자가 확인한 뒤 승인해요.',
            textAlign: TextAlign.center,
            style: BaraedaTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// 고른 학원 — 이름 · 지역 · 코드와 `변경`(시안 `signup`). 변경하면 학원 검색이 다시 열린다.
class _SelectedAcademyCard extends StatelessWidget {
  const new({required this.academy, required this.onChange});

  final AcademySummary academy;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '학원',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaCard(
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(BaraedaRadius.control),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: BaraedaIcon('school', color: colors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academy.name,
                      style: BaraedaTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: BaraedaFontWeight.bold,
                      ),
                    ),
                    Text(
                      '${academy.region} · 학원 코드 ${academy.code}',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              BaraedaButton(
                label: '변경',
                size: BaraedaButtonSize.sm,
                variant: BaraedaButtonVariant.ghost,
                onPressed: onChange,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
