import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';

/// AUTH-08 · API_SPEC §2.9 — 아이디·비밀번호 복구. **비인증 진입점**(로그인
/// 화면에서만 들어온다, `router.dart` 의 `redirect` 가 로그인 전 화면으로
/// 허용).
///
/// **계정 존재 여부 노출 주의.** 서버 자체가 `404 ACCOUNT_NOT_FOUND` 로
/// 미등록 전화번호를 구분해 응답한다(§2.9) — 이 화면이 문구를 더 파고들어
/// 구분하면 열거 공격을 오히려 쉽게 만든다. 그래서 `ACCOUNT_NOT_FOUND` 와
/// `VERIFICATION_CODE_INVALID` 를 **같은 문구**로 안내해 화면 단에서는
/// 추가로 구분해 주지 않는다(서버 응답 자체의 구분은 이 화면이 고칠 수
/// 있는 범위 밖이라 보고서 §2 에 남긴다).
///
/// **SMS 연동 전까지 서버가 `503 RECOVERY_UNAVAILABLE` 을 낸다**
/// (Ruling 329) — 문자 발송 수단이 없어 전화번호 인증이 성립하지 않는다.
/// 그동안의 복구는 관계자가 초기화하는 관리자 경유(§5.22)라 화면이
/// 처음부터 그 길을 안내한다.
class AccountRecoveryScreen extends ConsumerStatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  ConsumerState<AccountRecoveryScreen> createState() =>
      _AccountRecoveryScreenState();
}

/// 관리자 경유 복구 안내(Ruling 329) — 상시 안내와 503 응답이 같은 문구를 쓴다.
const _adminRecoveryNotice =
    '지금은 전화번호로 찾기를 준비 중입니다. 다니는 학원에 비밀번호 초기화를 요청해 주세요 — 아이디도 함께 알려드립니다';

class _AccountRecoveryScreenState extends ConsumerState<AccountRecoveryScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String _type = 'login_id';
  bool _codeRequested = false;
  bool _submitting = false;
  String? _banner;
  AlertTone _bannerTone = AlertTone.info;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// `ACCOUNT_NOT_FOUND`·`VERIFICATION_CODE_INVALID` 를 같은 문구로 묶는다
  /// (클래스 문서의 열거 위험 참고).
  String _messageFor(Failure failure) => switch (failure) {
    ApiFailure(code: 'ACCOUNT_NOT_FOUND') ||
    ApiFailure(
      code: 'VERIFICATION_CODE_INVALID',
    ) => '휴대폰 번호 또는 인증번호를 확인할 수 없습니다',
    ApiFailure(code: 'RECOVERY_UNAVAILABLE') => _adminRecoveryNotice,
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
        _banner = '인증번호를 발송했습니다. 문자로 받은 번호를 입력해 주세요';
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

  Future<void> _verifyCode() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (code.isEmpty || _submitting) return;

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
            ? '문자로 아이디를 보내드렸습니다'
            : '문자로 임시 비밀번호를 보내드렸습니다';
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_banner == null) ...[
                const AlertBanner(
                  tone: AlertTone.info,
                  body: _adminRecoveryNotice,
                ),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              BaraedaSelect(
                label: '찾을 항목',
                value: _type,
                enabled: !_codeRequested,
                options: const [
                  BaraedaSelectOption('login_id', label: '아이디'),
                  BaraedaSelectOption('password', label: '비밀번호'),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              BaraedaInput(
                label: '가입 시 등록한 휴대폰 번호',
                required: true,
                enabled: !_codeRequested,
                keyboardType: TextInputType.phone,
                controller: _phoneController,
              ),
              if (_codeRequested) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                BaraedaInput(
                  label: '인증번호',
                  required: true,
                  keyboardType: TextInputType.number,
                  controller: _codeController,
                ),
              ],
              if (_banner != null) ...[
                const SizedBox(height: BaraedaSpacing.space4),
                AlertBanner(tone: _bannerTone, body: _banner),
              ],
              const SizedBox(height: BaraedaSpacing.space6),
              // 버튼 비활성화만으로는 제출이 진행 중임이 드러나지 않는다 —
              // password_change_screen.dart 와 동일한 표시로 맞춘다(둘 다
              // 기능 결함이 아니라 표시 일관성 문제).
              if (_submitting) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              BaraedaButton(
                label: _codeRequested ? '확인하기' : '인증번호 받기',
                size: BaraedaButtonSize.lg,
                onPressed: _submitting
                    ? null
                    : (_codeRequested ? _verifyCode : _requestCode),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
