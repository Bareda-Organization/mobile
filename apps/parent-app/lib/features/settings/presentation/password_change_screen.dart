import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/credential_limits.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';

/// AUTH-07 · API_SPEC §2.8 — 비밀번호 변경.
///
/// 성공하면 서버가 기존 refresh 토큰을 전량 무효화한다(§2.8) — 이 화면이
/// 직접 재로그인 화면으로 보낸다. `authRepository.logout()` 을 함께
/// 부르지만 이미 서버 쪽 토큰은 무효화된 뒤라 그 API 호출 자체는 실패해도
/// 상관없다(`AuthApi.logout()` 이 성패와 무관하게 로컬 토큰을 지우는
/// `finally` 를 갖고 있음, `auth_api.dart` 참고) — 그래서 실패를 무시한다.
///
/// 임시 비밀번호 강제 변경(Ruling 540 · R46-LAST `Ruling 581`) 중이면 라우터가 이 화면에 고정한다 — 뒤로 갈
/// 길을 없애고 로그아웃만 연다(매니저 앱과 같은 갈래).
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PasswordChangeScreen> createState() =>
      _PasswordChangeScreenState();
}

/// [변경하기] 가 꺼진 이유 — 단추 바로 아래에 적는다. 눌러도 되면 `null`.
///
/// 꺼진 단추를 이유 없이 두면 사용자는 무엇을 더 해야 하는지 알 수 없다(막다른 길). 이유는 하나만 말한다 —
/// 가장 먼저 해결할 것(현재 비밀번호 → 새 비밀번호 → 길이 한도) 순서다.
String? passwordChangeBlockedReason({
  required String current,
  required String next,
}) {
  if (current.isEmpty && next.isEmpty) {
    return '현재 비밀번호와 새 비밀번호를 입력하면 눌러요';
  }
  if (current.isEmpty) return '현재 비밀번호를 입력하면 눌러요';
  if (next.isEmpty) return '새 비밀번호를 입력하면 눌러요';
  if (passwordLengthError(next) != null) {
    return '새 비밀번호를 한도 안으로 줄이면 눌러요';
  }
  return null;
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  /// 비밀번호 보기 단추 — 평소엔 가린다. 칸마다 따로다.
  bool _showCurrent = false;
  bool _showNew = false;

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
    if (passwordLengthError(newPassword) != null) return;

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
    final forced = ref.watch(mustChangePasswordProvider);
    final blockedReason = passwordChangeBlockedReason(
      current: _currentPasswordController.text,
      next: _newPasswordController.text,
    );

    return Scaffold(
      // 강제 변경 중에는 이 화면이 유일한 경로라 `onBack` 을 비우면
      // (`AppHeader` 가 뒤에 화면이 없으면 버튼을 안 그린다) 뒤로 가기가 없다.
      appBar: AppHeader(
        title: '비밀번호 변경',
        onBack: forced ? null : () => context.pop(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 바꾸면 모든 기기에서 로그아웃된다는 사실(§2.8 refresh 전량 무효화)을 입력 전에 먼저
                    // 알린다.
                    if (forced)
                      const AlertBanner(
                        tone: AlertTone.info,
                        title: '임시 비밀번호로 로그인했어요',
                        body: '관리자가 초기화한 비밀번호예요. 새 비밀번호로 바꿔야 앱을 계속 쓸 수 있어요.',
                      )
                    else
                      const AlertBanner(
                        tone: AlertTone.moving,
                        title: '바꾸면 모든 기기에서 로그아웃돼요.',
                        body: '새 비밀번호로 다시 로그인해 주세요.',
                      ),
                    const SizedBox(height: BaraedaSpacing.space4),
                    BaraedaInput(
                      label: '현재 비밀번호',
                      required: true,
                      kind: BaraedaInputKind.currentPassword,
                      obscureText: !_showCurrent,
                      suffix: _EyeButton(
                        shown: _showCurrent,
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                      error: _currentPasswordError,
                      controller: _currentPasswordController,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: BaraedaSpacing.space4),
                    BaraedaInput(
                      label: '새 비밀번호',
                      required: true,
                      kind: BaraedaInputKind.newPassword,
                      placeholder: '새 비밀번호',
                      hint: passwordLimitHint,
                      obscureText: !_showNew,
                      suffix: _EyeButton(
                        shown: _showNew,
                        onPressed: () => setState(() => _showNew = !_showNew),
                      ),
                      error: passwordLengthError(_newPasswordController.text),
                      controller: _newPasswordController,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: BaraedaSpacing.space4),
                      AlertBanner(tone: AlertTone.missed, body: _formError),
                    ],
                    // 버튼 비활성화만으로는 제출이 진행 중임이 드러나지 않는다 — 이 앱의 다른 화면이 데이터 로딩 중에
                    // 쓰는 것과 같은 `CircularProgressIndicator` 를 제출 중에도 보여준다(표시
                    // 일관성).
                    if (_submitting) ...[
                      const SizedBox(height: BaraedaSpacing.space6),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),
            // 주 행동은 엄지가 닿는 맨 아래에 고정한다. 꺼져 있으면 이유가 단추 바로 아래에 붙는다.
            StickyActionBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BaraedaButton(
                    label: '변경하기',
                    size: BaraedaButtonSize.xl,
                    block: true,
                    disabledReason: _submitting ? null : blockedReason,
                    onPressed: _submitting || blockedReason != null
                        ? null
                        : _submit,
                  ),
                  if (forced)
                    BaraedaButton(
                      label: '로그아웃',
                      variant: BaraedaButtonVariant.ghost,
                      block: true,
                      onPressed: _submitting
                          ? null
                          : () => unawaited(confirmLogout(context, ref)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력칸 안 오른쪽 "비밀번호 보기" 단추(시안) — 눈 모양, 누르면 가림이 바뀐다.
class _EyeButton extends StatelessWidget {
  const new({required this.shown, required this.onPressed});

  final bool shown;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BaraedaIconButton(
      icon: shown ? 'eye-off' : 'eye',
      label: shown ? '비밀번호 가리기' : '비밀번호 보기',
      onPressed: onPressed,
    );
  }
}
