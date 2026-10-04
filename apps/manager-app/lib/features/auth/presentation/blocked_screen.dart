import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/manager_header.dart';

/// UF-X-04 — 계정 차단 안내(시안 `blocked`).
///
/// 로그인 자체가 `403 AUTH_ACCOUNT_BLOCKED` 로 실패한 결과라 토큰·role·status 어느 것도 만들어지지
/// 않는다 —
/// `router.dart` 의 declarative `redirect` 로는 표현할 수 없어 `LoginScreen` 이 이 화면을
/// 직접 `context.push`
/// 한다(`app/router.dart` 의 redirect 는 이 경로를 벗어나게 하지 않도록 예외 처리돼 있다).
///
/// 차단 범위는 계정 단위뿐이다(IP 차단 아님) — 다른 기기·다른 계정 로그인은 이 화면과 무관하다. 자가 해제 수단은
/// 없고 학원 관리자만 해제할 수 있어, 이 화면은 안내와 학원 전화, 로그인 화면 복귀만 제공한다.
///
/// 학원 전화번호는 **이 기기가 마지막 로그인 성공(응답 · `/me` 의 `academy.contact`)에서 저장해 둔 값**이다
/// (`Ruling 825`) — 잠긴 계정은 서버에서 번호를 받을 수 없다. 저장된 번호가 없거나 번호 모양이 아니면 전화
/// 단추 대신 "다니는 학원에 문의해 주세요" 문장을 보인다.
class BlockedScreen extends ConsumerWidget {
  /// `/blocked-account`. `LoginScreen` 이 `context.push` 로만 진입시킨다.
  const new({super.key});

  /// 저장된 번호가 없을 때 전화 단추 자리에 놓는 문장.
  static const noContactNotice = '다니는 학원에 문의해 주세요';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // 이 기기에 저장된 번호가 우선이고, 앱이 켜져 있는 동안 받은 값(메모리)이 보조다.
    final saved =
        ref.watch(savedAcademyContactProvider).value ??
        ref.watch(academyContactProvider);
    final number = looksLikePhoneNumber(saved) ? saved!.trim() : null;

    return Scaffold(
      appBar: ManagerHeader(
        title: '계정 잠김',
        showSos: false,
        onBack: () => context.pop(),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.statusMissedSoft,
                    ),
                    child: BaraedaIcon(
                      'lock',
                      size: 32,
                      color: colors.statusMissed,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '계정이 잠겼어요',
                  textAlign: TextAlign.center,
                  style: BaraedaTypography.h3.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '로그인에 5번 연속 실패해서 이 계정이 잠겼어요.\n'
                  '다른 기기나 다른 계정에는 영향이 없어요.',
                  textAlign: TextAlign.center,
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                const BaraedaCard(
                  child: StopTimeline(
                    stops: [
                      Stop(
                        name: '학원 관리자에게 알리기',
                        address: '잠금은 학원 관리자만 풀 수 있어요',
                        state: StopState.current,
                      ),
                      Stop(name: '풀리면 다시 로그인', address: '스스로 풀 방법은 없어요'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (number != null)
                  BaraedaButton(
                    label: '학원에 전화 · $number',
                    icon: 'phone',
                    size: BaraedaButtonSize.xl,
                    block: true,
                    onPressed: () => unawaited(
                      ref.read(uriOpenerProvider)(
                        Uri(scheme: 'tel', path: number),
                      ),
                    ),
                  )
                else
                  BaraedaCard(
                    tone: BaraedaCardTone.mist,
                    child: Text(
                      noContactNotice,
                      textAlign: TextAlign.center,
                      style: BaraedaTypography.body.copyWith(
                        color: colors.textBrand,
                        fontWeight: BaraedaFontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.bgBase,
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: BaraedaButton(
                  label: '로그인 화면으로',
                  variant: BaraedaButtonVariant.secondary,
                  block: true,
                  onPressed: () => context.pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
