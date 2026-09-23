import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';

/// UF-X-03 — 로그인 폼 → `POST /auth/login` → 성공하면 역할·상태 provider 를
/// 채운다. 이후 화면 전환은 이 화면이 직접 `go` 하지 않는다 —
/// `RouterRefreshNotifier` 가 provider 변화를 듣고 `router.dart` 의
/// `redirect` 를 다시 돌려 자동으로 넘어간다(§ 아키텍처 결정 2).
///
/// 이 화면이 직접 처리하는 예외 2가지(§ 아키텍처 결정 2, 라우터가 판정할
/// 수 없는 것들):
/// - **지원하지 않는 역할**(`role` 이 이 앱이 모르는 값) — 5번째 화면을
///   새로 만들지 않고 인라인 안내 + 로그아웃으로 끝낸다.
/// - **차단 계정**(`403 AUTH_ACCOUNT_BLOCKED`) — 로그인 자체가 실패해
///   토큰·role·status 어느 것도 생기지 않으므로 라우터 게이트로 잡을 수
///   없다. [AppRoutes.blockedAccount] 로 직접 `push` 한다(UF-X-04).
///
/// `parent_app` 의 같은 화면과 로직이 같다(§1.1) — 앱 제목만 다르다.
class LoginScreen extends ConsumerStatefulWidget {
  /// 앱 시작 · 로그아웃 후 진입 라우트(`/login`).
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _passwordError;
  String? _formError;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loginId = _loginIdController.text.trim();
    final password = _passwordController.text;
    if (loginId.isEmpty || password.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _passwordError = null;
      _formError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final response = await repository.login(
        loginId: loginId,
        password: password,
      );
      applyRoleAndStatus(
        ref.read(unsupportedRoleProvider.notifier),
        ref.read(currentUserRoleProvider.notifier),
        ref.read(currentAccountStatusProvider.notifier),
        role: response.role,
        status: response.status,
      );

      if (ref.read(unsupportedRoleProvider)) {
        // 로그인 자체는 서버 기준 성공이라 토큰이 이미 저장돼 있다 —
        // 이 앱에서는 쓸 수 없는 계정이므로 즉시 무효화한다.
        await repository.logout();
        ref.read(unsupportedRoleProvider.notifier).state = false;
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _formError = '이 계정은 이 앱에서 지원하지 않는 계정입니다';
        });
        return;
      }
      // 그 외에는 router 의 redirect 가 role/status 변화를 듣고 알아서
      // 다음 화면(홈 또는 대기 화면)으로 넘긴다 — 여기서 `context.go` 하지
      // 않는다.
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        switch (failure) {
          case ApiFailure(code: 'INVALID_CREDENTIALS', :final details):
            final remaining = details?['remaining_attempts'];
            _passwordError = remaining == null
                ? '아이디 또는 비밀번호가 올바르지 않습니다'
                : '아이디 또는 비밀번호가 올바르지 않습니다 (잔여 시도 $remaining회)';
          case ApiFailure(code: 'AUTH_ACCOUNT_BLOCKED'):
            _formError = null;
            _passwordError = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(context.push(AppRoutes.blockedAccount));
            });
          case ApiFailure(:final message):
            _formError = message;
          case NetworkFailure():
            _formError = '네트워크 상태를 확인해 주세요';
          default:
            _formError = '로그인에 실패했습니다';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = '로그인에 실패했습니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: BaraedaSpacing.space16),
              const Text('바래다 매니저', style: BaraedaTypography.h1),
              const SizedBox(height: BaraedaSpacing.space8),
              BaraedaInput(
                label: '아이디',
                required: true,
                controller: _loginIdController,
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '비밀번호',
                required: true,
                obscureText: true,
                error: _passwordError,
                controller: _passwordController,
              ),
              if (_formError != null) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                AlertBanner(tone: AlertTone.missed, body: _formError),
              ],
              const SizedBox(height: BaraedaSpacing.space6),
              BaraedaButton(
                label: '로그인하기',
                size: BaraedaButtonSize.lg,
                onPressed: _submitting ? null : _submit,
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaButton(
                label: '회원가입하기',
                size: BaraedaButtonSize.lg,
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => context.go(AppRoutes.signup),
              ),
              DevQuickLogin(
                accounts: const [
                  DevAccount('기사', 'driverA1'),
                  DevAccount('동승자', 'escortA1'),
                  // 시드에서 **운행 중(moving)** 인 회차 3의 동승자 — 승하차 처리를
                  // 눈으로 보려면 이 계정이어야 한다(다른 동승자의 회차는 출발 전이다).
                  DevAccount('동승자(운행중)', 'escortA2'),
                  DevAccount('기사(타 학원)', 'driverB1'),
                  DevAccount('차단됨', 'driverBlocked'),
                  // V14 데모 학원(목동) 1호차 — 승하차지 15곳 · 학생 20명 명단.
                  DevAccount('데모 기사', 'driver011'),
                  DevAccount('데모 동승자', 'escort011'),
                ],
                onPick: (loginId, password) {
                  _loginIdController.text = loginId;
                  _passwordController.text = password;
                  _submit();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
