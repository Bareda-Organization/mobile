import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';

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
  const new({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _passwordError;
  String? _formError;

  /// 서버가 알려 준 남은 시도 횟수(`remaining_attempts`) — 한도 안내(M14)에 쓴다. 모르면 `null`.
  int? _remainingAttempts;

  /// 잔여 시도가 이 값 이하이면 잠금 경고 띠를 보인다(학부모 앱과 같다, B2).
  static const _lockWarningThreshold = 2;

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
      _remainingAttempts = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final response = await repository.login(
        loginId: loginId,
        password: password,
      );
      applyLoginResponse(ref, response);

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
            _passwordError = '아이디 또는 비밀번호가 올바르지 않아요';
            final remaining = details?['remaining_attempts'];
            _remainingAttempts = remaining is int ? remaining : null;
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
    final colors = context.colors;
    // 로그인이 만료돼 돌아왔다면 이유를 알린다(R46) — 이유 없이 로그인 화면만 나오면 오류인 줄 안다.
    final expiredNotice = ref.watch(sessionExpiredNoticeProvider);
    final remaining = _remainingAttempts;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colors.accentPrimary,
                            borderRadius: BorderRadius.circular(
                              BaraedaRadius.card,
                            ),
                          ),
                          child: BaraedaIcon(
                            'bus',
                            size: 28,
                            color: colors.textInverse,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '바래다 매니저',
                                style: BaraedaTypography.h3.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                '기사 · 동승자',
                                style: BaraedaTypography.body.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (expiredNotice != null) ...[
                      AlertBanner(tone: AlertTone.moving, body: expiredNotice),
                      const SizedBox(height: 16),
                    ],
                    BaraedaInput(
                      label: '아이디',
                      kind: BaraedaInputKind.username,
                      controller: _loginIdController,
                    ),
                    const SizedBox(height: 16),
                    BaraedaInput(
                      label: '비밀번호',
                      kind: BaraedaInputKind.currentPassword,
                      obscureText: true,
                      error: _passwordError,
                      controller: _passwordController,
                    ),
                    if (remaining != null &&
                        remaining <= _lockWarningThreshold) ...[
                      const SizedBox(height: 12),
                      AlertBanner(
                        tone: AlertTone.missed,
                        title: '$remaining번 더 틀리면 계정이 잠겨요',
                        body:
                            '5번 연속 실패하면 메인 관리자가 풀어 줄 때까지 '
                            '로그인할 수 없어요.',
                      ),
                    ],
                    if (_formError != null) ...[
                      const SizedBox(height: 12),
                      AlertBanner(tone: AlertTone.missed, body: _formError),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '한 번 로그인하면 이 기기에서 자동으로 로그인돼요. 다른 사람과 같이 쓰는 '
                      '폰이면 사용 후 로그아웃해 주세요.',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // M5(Ruling 329 · UF-X-04) — 매니저(기사·동승자)도 학부모·학생과 같은 "학원
                    // 관계자 경유"
                    // 복구만 연다. 전화번호 복구 화면(SMS 연동 전 503, §5.22)은 만들지 않고 안내만 둔다.
                    Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(
                            text: '비밀번호를 잊으셨나요? ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: '다니는 학원에 초기화를 요청해 주세요. '),
                          TextSpan(
                            text: '임시 비밀번호',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: '를 받아 로그인할 수 있어요.'),
                        ],
                      ),
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.bgBase,
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BaraedaButton(
                      label: '로그인',
                      size: BaraedaButtonSize.xl,
                      block: true,
                      onPressed: _submitting ? null : _submit,
                    ),
                    const SizedBox(height: 8),
                    BaraedaButton(
                      label: '처음이세요? 회원가입',
                      variant: BaraedaButtonVariant.secondary,
                      block: true,
                      onPressed: () => context.push(AppRoutes.signup),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
