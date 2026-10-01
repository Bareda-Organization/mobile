import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';

/// AUTH-07 · API_SPEC §2.8 — 비밀번호 변경(기사·동승자 공통, R32 M13).
///
/// 학부모 앱의 같은 화면을 본보기로 이 앱 안에 만들었다(공유 패키지로 옮기지 않는다). 성공하면
/// 서버가 기존 refresh 토큰을 전량 무효화한다(§2.8) — 그래서 이 기기도 로그아웃해 다시 로그인하게
/// 한다. 로그아웃 호출은 서버 쪽 토큰이 이미 무효라 실패해도 상관없다(`AuthApi.logout` 이 성패와
/// 무관하게 로컬 토큰을 지운다). 역할이 비면 라우터가 로그인 화면으로 보낸다.
///
/// 임시 비밀번호 강제 변경(Ruling 540) 중이면 라우터가 이 화면에 고정한다 — 뒤로 갈 길을 없애고 로그아웃만 연다.
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  ConsumerState<PasswordChangeScreen> createState() =>
      _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _submitting = false;
  String? _currentPasswordError;
  String? _formError;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    if (currentPassword.isEmpty || newPassword.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _currentPasswordError = null;
      _formError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    // 화면이 사라지기 전에 읽어 둔다 — 로그아웃하면 이 화면은 곧 내려간다.
    final unsupported = ref.read(unsupportedRoleProvider.notifier);
    final role = ref.read(currentUserRoleProvider.notifier);
    final status = ref.read(currentAccountStatusProvider.notifier);
    try {
      await repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      try {
        await repository.logout();
      } on Failure {
        // 서버가 이미 refresh 토큰을 전량 무효화했으니 실패해도 된다.
      }
      applyRoleAndStatus(unsupported, role, status, role: null, status: null);
      if (mounted) setState(() => _submitting = false);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (failure) {
          case ApiFailure(code: 'INVALID_CREDENTIALS'):
            _currentPasswordError = '현재 비밀번호가 올바르지 않습니다';
          case ApiFailure(code: 'VALIDATION_FAILED'):
            _formError = '입력값을 다시 확인해 주세요';
          default:
            _formError = describeFailure(failure);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = ref.watch(mustChangePasswordProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('비밀번호 변경'),
        automaticallyImplyLeading: false,
        leading: forced ? null : BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (forced) ...[
                const AlertBanner(
                  tone: AlertTone.info,
                  body: '관리자가 초기화한 임시 비밀번호입니다. 새 비밀번호로 바꿔야 앱을 계속 쓸 수 있습니다',
                ),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              BaraedaInput(
                label: '현재 비밀번호',
                required: true,
                obscureText: true,
                error: _currentPasswordError,
                controller: _currentPasswordController,
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '새 비밀번호',
                required: true,
                obscureText: true,
                controller: _newPasswordController,
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              const WordWrapText('바꾸면 이 기기에서 로그아웃되고, 새 비밀번호로 다시 로그인해야 합니다'),
              if (_formError != null) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                AlertBanner(tone: AlertTone.missed, body: _formError),
              ],
              const SizedBox(height: BaraedaSpacing.space6),
              if (_submitting) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              BaraedaButton(
                label: '변경하기',
                size: BaraedaButtonSize.lg,
                onPressed: _submitting ? null : _submit,
              ),
              if (forced) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                TextButton(
                  onPressed: _submitting ? null : () => signOut(ref),
                  child: const Text('로그아웃'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
