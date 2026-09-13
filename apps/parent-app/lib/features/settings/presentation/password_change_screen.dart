import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';

/// AUTH-07 · API_SPEC §2.8 — 비밀번호 변경.
///
/// 성공하면 서버가 기존 refresh 토큰을 전량 무효화한다(§2.8) — 이 화면이
/// 직접 재로그인 화면으로 보낸다. `authRepository.logout()` 을 함께
/// 부르지만 이미 서버 쪽 토큰은 무효화된 뒤라 그 API 호출 자체는 실패해도
/// 상관없다(`AuthApi.logout()` 이 성패와 무관하게 로컬 토큰을 지우는
/// `finally` 를 갖고 있음, `auth_api.dart` 참고) — 그래서 실패를 무시한다.
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
    try {
      await repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      try {
        await repository.logout();
      } on Failure {
        // 서버가 이미 refresh 토큰을 전량 무효화했으니 이 호출은 실패해도
        // 된다 — 로컬 토큰은 `AuthApi.logout()` 의 `finally` 가 지운다.
      }
      if (!mounted) return;
      applyRoleAndStatus(
        ref.read(unsupportedRoleProvider.notifier),
        ref.read(currentUserRoleProvider.notifier),
        ref.read(currentAccountStatusProvider.notifier),
        role: null,
        status: null,
      );
      // router 의 redirect 가 role=null 을 보고 로그인 화면으로 옮긴다
      // (login_screen.dart 와 같은 방식, 여기서 context.go 하지 않는다).
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (failure) {
          case ApiFailure(code: 'INVALID_CREDENTIALS'):
            _currentPasswordError = '현재 비밀번호가 올바르지 않습니다';
          case ApiFailure(code: 'VALIDATION_FAILED'):
            _formError = '입력값을 다시 확인해 주세요';
          case ApiFailure(:final message):
            _formError = message;
          case NetworkFailure():
            _formError = '네트워크 상태를 확인해 주세요';
          default:
            _formError = '비밀번호를 바꾸지 못했습니다';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: '비밀번호 변경', onBack: () => context.pop()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (_formError != null) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                AlertBanner(tone: AlertTone.missed, body: _formError),
              ],
              const SizedBox(height: BaraedaSpacing.space6),
              // 버튼 비활성화만으로는 제출이 진행 중임이 드러나지 않는다 —
              // 이 앱의 다른 화면이 데이터 로딩 중에 쓰는 것과 같은
              // `CircularProgressIndicator` 를 제출 중에도 보여준다
              // (`pending_approval_screen.dart`·
              // `device_registration_panel.dart` 의 로딩 표시와 같은 형태,
              // `account_recovery_screen.dart` 와도 동일하게 맞춘다 —
              // 기능 결함이 아니라 표시 일관성 문제다).
              if (_submitting) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              BaraedaButton(
                label: '변경하기',
                size: BaraedaButtonSize.lg,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
