import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/auth/presentation/widgets/academy_picker.dart';

/// UF-X-01 — 회원가입: 아이디·비밀번호·이름·연락처 → 역할 선택(버스기사·동승자) →
/// 학원 검색·선택 → `POST /auth/signup` → `pending`.
///
/// 성공해도 토큰은 발급되지 않는다(§2.2) — 로그인 화면으로 돌려보낸다.
/// `parent_app` 의 같은 화면과 구조가 같고, 역할 선택지만 이 앱이 담당하는
/// 2종(`role_policy.dart` 의 "버스기사(`driver`)"·"동승자(`escort`)")으로
/// 바뀐다(§1.1).
class SignupScreen extends ConsumerStatefulWidget {
  /// 이 앱 라우트(`/signup`)로만 진입한다.
  const SignupScreen({super.key});

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

  bool get _canSubmit =>
      !_submitting &&
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
      // 서버가 201 을 확정한 뒤에만 안내한다 — 낙관적 UI 금지(COMMON.md §6).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가입 신청이 접수되었습니다. 로그인 후 진행 상황을 볼 수 있습니다.')),
      );
      context.go(AppRoutes.login);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (failure) {
          case ApiFailure(code: 'DUPLICATE_LOGIN_ID'):
            _loginIdError = '이미 사용 중인 아이디입니다';
          case ApiFailure(code: 'ACADEMY_NOT_FOUND'):
            _formError = '학원을 찾을 수 없습니다 — 학원에 문의해 주세요';
          case ApiFailure(:final message):
            _formError = message;
          case NetworkFailure():
            _formError = '네트워크 상태를 확인해 주세요';
          default:
            _formError = '가입 신청에 실패했습니다';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = '가입 신청에 실패했습니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BaraedaSegmentedControl(
                options: const [
                  BaraedaSegmentedOption('driver', label: '버스기사'),
                  BaraedaSegmentedOption('escort', label: '동승자'),
                ],
                value: _role,
                block: true,
                onChanged: (value) => setState(() => _role = value),
              ),
              const SizedBox(height: BaraedaSpacing.space5),
              BaraedaInput(
                label: '아이디',
                required: true,
                controller: _loginIdController,
                error: _loginIdError,
                onChanged: (_) {
                  if (_loginIdError != null) {
                    setState(() => _loginIdError = null);
                  }
                  setState(() {});
                },
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '비밀번호',
                required: true,
                obscureText: true,
                controller: _passwordController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '이름',
                required: true,
                controller: _nameController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '연락처',
                required: true,
                keyboardType: TextInputType.phone,
                controller: _phoneController,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: BaraedaSpacing.space5),
              AcademyPicker(
                onSearch: repository.searchAcademies,
                selected: _academy,
                onSelected: (academy) => setState(() => _academy = academy),
              ),
              if (_formError != null) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                AlertBanner(tone: AlertTone.missed, body: _formError),
              ],
              const SizedBox(height: BaraedaSpacing.space6),
              BaraedaButton(
                label: '가입 신청하기',
                size: BaraedaButtonSize.lg,
                block: true,
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
