import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:url_launcher/url_launcher.dart';

/// UF-X-04 — 계정 차단 안내.
///
/// 로그인 자체가 `403 AUTH_ACCOUNT_BLOCKED` 로 실패한 결과라 토큰·role·
/// status 어느 것도 만들어지지 않는다 — `router.dart` 의 declarative
/// `redirect` 로는 표현할 수 없어 `LoginScreen` 이 이 화면을 직접
/// `context.push` 한다(`app/router.dart` 의 redirect 는 이 경로를 벗어나게
/// 하지 않도록 예외 처리돼 있다).
///
/// 차단 범위는 계정 단위뿐이다(IP 차단 아님) — 다른 기기·다른 계정 로그인은
/// 이 화면과 무관하다. 자가 해제 수단은 없고 학원 메인 관리자만 해제할 수 있지만, 사용자에게는
/// 그 구분을 알릴 이유가 없어 문의처를 "학원" 하나로만 적는다(R32 P13).
///
/// 토큰이 없어 소속 학원을 모르므로 **기기에 저장한 마지막 학원 문의처**(승인 대기 화면이 남긴 것)에 전화번호가
/// 있으면 `학원에 전화` 단추를 주 단추로 둔다. 없으면 단추 없이 "다니는 학원에 문의해 주세요" 문장만 남는다
/// (`Ruling 825`).
class BlockedScreen extends ConsumerWidget {
  /// `/blocked-account`. `LoginScreen` 이 `context.push` 로만 진입시킨다.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final phone = phoneNumberOf(ref.watch(savedAcademyContactProvider).value);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: BaraedaSpacing.space6),
                    const Center(
                      child: BaraedaIcon('lock', size: 48),
                    ),
                    const SizedBox(height: BaraedaSpacing.space4),
                    Semantics(
                      header: true,
                      child: const Text(
                        '계정이 잠겼어요',
                        textAlign: TextAlign.center,
                        style: BaraedaTypography.h2,
                      ),
                    ),
                    const SizedBox(height: BaraedaSpacing.space3),
                    Text(
                      '비밀번호를 5번 틀려서 이 계정이 잠겼습니다.\n'
                      '직접 풀 수는 없으니 다니는 학원에 문의해 주세요.',
                      textAlign: TextAlign.center,
                      style: BaraedaTypography.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: BaraedaSpacing.space6),
                    const AlertBanner(
                      tone: AlertTone.info,
                      title: '학원이 잠금을 풀면 바로 다시 로그인 할 수 있어요.',
                      body: '잠긴 것은 이 계정뿐이에요. 다른 계정은 그대로 써요.',
                    ),
                  ],
                ),
              ),
              if (phone != null) ...[
                BaraedaButton(
                  label: '학원에 전화 · $phone',
                  icon: 'phone',
                  block: true,
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                ),
                const SizedBox(height: BaraedaSpacing.space2),
              ],
              BaraedaButton(
                label: '로그인 화면으로 돌아가기',
                variant: phone != null
                    ? BaraedaButtonVariant.ghost
                    : BaraedaButtonVariant.primary,
                block: true,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
