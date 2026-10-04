import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/credential_limits.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/manager_header.dart';

/// AUTH-07 · API_SPEC §2.8 — 비밀번호 변경(기사·동승자 공통, R32 M13).
///
/// 학부모 앱의 같은 화면을 본보기로 이 앱 안에 만들었다(공유 패키지로 옮기지 않는다). 성공하면
/// 서버가 기존 refresh 토큰을 전량 무효화한다(§2.8) — 그래서 이 기기도 로그아웃해 다시 로그인하게
/// 한다. 로그아웃 호출은 서버 쪽 토큰이 이미 무효라 실패해도 상관없다(`AuthApi.logout` 이 성패와
/// 무관하게 로컬 토큰을 지운다). 역할이 비면 라우터가 로그인 화면으로 보낸다.
///
/// 임시 비밀번호 강제 변경(Ruling 540) 중이면 라우터가 이 화면에 고정한다 — 뒤로 갈 길을 없애고 로그아웃만 연다.
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const new({super.key});

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

  /// 단추가 꺼진 이유 — 꺼져 있으면 단추 아래에 그대로 적는다(M15). 켜져 있으면 `null`.
  String? get _disabledReason {
    if (_currentPasswordController.text.isEmpty) {
      return '현재 비밀번호를 입력하면 눌러요';
    }
    final next = _newPasswordController.text;
    if (next.isEmpty) return '새 비밀번호를 입력하면 눌러요';
    if (passwordLengthError(next) != null) return '새 비밀번호를 줄이면 눌러요';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final forced = ref.watch(mustChangePasswordProvider);
    final colors = context.colors;
    final reason = _disabledReason;
    return Scaffold(
      // 강제 변경(임시 비밀번호)은 뒤로 갈 곳이 없다 — 라우터가 이 화면에 고정한다.
      appBar: const ManagerHeader(title: '비밀번호 변경', showSos: false),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (forced) ...[
                    const AlertBanner(
                      tone: AlertTone.moving,
                      icon: 'lock',
                      title: '임시 비밀번호로 로그인했어요',
                      body: '관리자가 초기화한 비밀번호예요. 새 비밀번호로 바꿔야 앱을 계속 쓸 수 있어요.',
                    ),
                    const SizedBox(height: BaraedaSpacing.space4),
                  ],
                  BaraedaInput(
                    label: forced ? '현재 비밀번호(임시)' : '현재 비밀번호',
                    obscureText: true,
                    kind: BaraedaInputKind.currentPassword,
                    error: _currentPasswordError,
                    controller: _currentPasswordController,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: BaraedaSpacing.space4),
                  // 한도(M14) — 서버는 UTF-8 72바이트를 넘으면 422 로 거절한다. 입력하는 동안 미리 알린다.
                  BaraedaInput(
                    label: '새 비밀번호',
                    hint: '영문 72자 · 한글 24자까지',
                    obscureText: true,
                    kind: BaraedaInputKind.newPassword,
                    error: passwordLengthError(_newPasswordController.text),
                    controller: _newPasswordController,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: BaraedaSpacing.space4),
                  BaraedaCard(
                    tone: BaraedaCardTone.mist,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BaraedaIcon('info', color: colors.textBrand),
                        const SizedBox(width: BaraedaSpacing.space3),
                        Expanded(
                          child: WordWrapText(
                            '바꾸면 이 기기에서 로그아웃돼요. 새 비밀번호로 다시 로그인해 주세요.',
                            style: BaraedaTypography.body.copyWith(
                              color: colors.textBrand,
                              fontWeight: BaraedaFontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: BaraedaSpacing.space4),
                    AlertBanner(tone: AlertTone.missed, body: _formError),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: BaraedaSpacing.space4),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
          BottomActionBar(
            children: [
              BaraedaButton(
                label: '변경하기',
                size: BaraedaButtonSize.xl,
                block: true,
                onPressed: _submitting || reason != null ? null : _submit,
                disabledReason: _submitting ? null : reason,
              ),
              if (forced) ...[
                const SizedBox(height: BaraedaSpacing.space2),
                BaraedaButton(
                  label: '로그아웃',
                  variant: BaraedaButtonVariant.ghost,
                  block: true,
                  onPressed: _submitting ? null : () => signOut(ref),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
