import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';

/// UF-X-01 — 회원가입: 아이디·비밀번호·이름·연락처 → 역할 선택(학부모·학생) →
/// 학원 검색·선택 → `POST /auth/signup` → `pending`.
///
/// 가입 응답에는 토큰이 없다(§2.2). 그래도 `pending` 계정은 로그인이 되므로(§2.5) 방금 입력한 아이디·비밀번호로
/// 바로 로그인해 승인 대기 화면으로 들어간다. 그 로그인이 실패하면 로그인 화면으로 돌려보낸다.
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

  String _role = 'parent';
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

  bool get _canSubmit =>
      !_submitting &&
      loginIdLengthError(_loginIdController.text) == null &&
      passwordLengthError(_passwordController.text) == null &&
      _academy != null &&
      _loginIdController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty;

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

  /// 가입 직후 자동 로그인 — 성공하면 역할·상태만 채우고 화면 전환은 라우터에 맡긴다(`LoginScreen` 과 같은 방식).
  /// 실패하면 가입은 이미 접수됐으니 로그인 화면으로 돌려보내 직접 로그인하게 한다.
  Future<void> _signInAfterSignup(AuthRepository repository) async {
    try {
      final response = await repository.login(
        loginId: _loginIdController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      applyRoleAndStatus(
        ref.read(unsupportedRoleProvider.notifier),
        ref.read(currentUserRoleProvider.notifier),
        ref.read(currentAccountStatusProvider.notifier),
        role: response.role,
        status: response.status,
      );
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

  /// 아직 비어 있는 항목 이름 — [가입 신청하기] 가 꺼져 있는 이유를 알린다. 길이 오류는 그 입력칸 옆에 따로 뜬다.
  List<String> get _emptyFields => [
    if (_loginIdController.text.trim().isEmpty) '아이디',
    if (_passwordController.text.isEmpty) '비밀번호',
    if (_nameController.text.trim().isEmpty) '이름',
    if (_phoneController.text.trim().isEmpty) '연락처',
    if (_academy == null) '학원',
  ];

  /// 한도를 넘어 [가입 신청하기] 가 꺼진 이유 — 단추 바로 아래에 적는다. 넘지 않았으면 `null`.
  String? get _overLimitReason {
    if (isPasswordTooShort(_passwordController.text)) {
      return passwordTooShortMessage;
    }
    final over = [
      if (loginIdLengthError(_loginIdController.text) != null) '아이디',
      if (passwordLengthError(_passwordController.text) != null) '비밀번호',
    ];
    return over.isEmpty ? null : '${over.join('·')}를 한도 안으로 줄이면 눌러요';
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    final emptyFields = _emptyFields;
    final overLimitReason = _overLimitReason;

    return Scaffold(
      appBar: const AppHeader(title: '회원가입'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoleSection(
                      role: _role,
                      onChanged: (value) => setState(() => _role = value),
                    ),
                    const SizedBox(height: BaraedaSpacing.space5),
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
                    _AcademySection(
                      onSearch: repository.searchAcademies,
                      selected: _academy,
                      onSelected: (academy) =>
                          setState(() => _academy = academy),
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
              overLimitReason: _submitting ? null : overLimitReason,
              emptyFields: _submitting ? const [] : emptyFields,
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력 묶음 머리글 — `누구세요?` · `계정 정보` · `다니는 학원`.
class _SectionLabel extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Text(
        text,
        style: BaraedaTypography.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: BaraedaFontWeight.bold,
        ),
      ),
    );
  }
}

/// 가입 역할(학부모 · 학생) 선택.
class _RoleSection extends StatelessWidget {
  const new({required this.role, required this.onChanged});

  final String role;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 승인이 필요하다는 것을 가입 전에 먼저 알린다(가입한 뒤에야 알게 되던 것).
        const AlertBanner(
          tone: AlertTone.info,
          title: '가입을 신청하면 학원 관계자가 승인한 뒤에 쓸 수 있어요.',
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        const _SectionLabel('누구세요?'),
        BaraedaSegmentedControl(
          options: const [
            BaraedaSegmentedOption('parent', label: '학부모'),
            BaraedaSegmentedOption('student', label: '학생'),
          ],
          value: role,
          block: true,
          onChanged: onChanged,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('계정 정보'),
        BaraedaInput(
          label: '아이디',
          announceRequired: true,
          hint: '$loginIdMaxLength자 이하',
          controller: loginIdController,
          error: loginIdError ?? loginIdLengthError(loginIdController.text),
          onChanged: (_) => onLoginIdChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '비밀번호',
          announceRequired: true,
          obscureText: true,
          hint: passwordLimitHint,
          error: passwordLengthError(passwordController.text),
          controller: passwordController,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '이름',
          announceRequired: true,
          placeholder: '실명을 입력해 주세요',
          controller: nameController,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaInput(
          label: '연락처',
          announceRequired: true,
          placeholder: '010-0000-0000',
          keyboardType: TextInputType.phone,
          controller: phoneController,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

/// 주 행동은 엄지가 닿는 맨 아래에 고정한다 — 꺼져 있으면 무엇이 비었는지를 단추 바로 아래에 적는다.
class _SignupActionBar extends StatelessWidget {
  const new({
    required this.onSubmit,
    required this.overLimitReason,
    required this.emptyFields,
  });

  final VoidCallback? onSubmit;
  final String? overLimitReason;
  final List<String> emptyFields;

  @override
  Widget build(BuildContext context) {
    final overLimitReason = this.overLimitReason;
    return StickyActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BaraedaButton(
            label: '가입 신청하기',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: onSubmit,
          ),
          if (overLimitReason != null) ...[
            const SizedBox(height: BaraedaSpacing.space2),
            WordWrapText(
              overLimitReason,
              textAlign: TextAlign.center,
              style: BaraedaTypography.bodySm,
            ),
          ],
          if (emptyFields.isNotEmpty) ...[
            const SizedBox(height: BaraedaSpacing.space2),
            WordWrapText(
              '아직 채우지 않은 항목 · ${emptyFields.join(' · ')}',
              textAlign: TextAlign.center,
              style: BaraedaTypography.bodySm,
            ),
          ],
        ],
      ),
    );
  }
}

/// 다니는 학원 검색 · 선택.
class _AcademySection extends StatelessWidget {
  const new({
    required this.onSearch,
    required this.selected,
    required this.onSelected,
  });

  final Future<List<AcademySummary>> Function(String query) onSearch;
  final AcademySummary? selected;
  final ValueChanged<AcademySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: BaraedaSpacing.space5),
        const _SectionLabel('다니는 학원'),
        AcademyPicker(
          style: AcademyPickerStyle.radioList,
          onSearch: onSearch,
          selected: selected,
          onSelected: onSelected,
        ),
      ],
    );
  }
}
