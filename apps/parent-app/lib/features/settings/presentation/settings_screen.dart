import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/features/settings/presentation/widgets/notification_settings_panel.dart';

/// 설정 화면 — P-09 (IMPLEMENTATION_PLAN.md §3.1, §3.14 · §2.11 · §2.8).
///
/// UF-S-01 확인 결과 이 화면은 역할별로 감출 항목이 없다 — 학생 계정도
/// 알림 설정(S-03)에 그대로 접근한다(학생에게 감추는 것은 "탑승 토글·
/// 일일 스케줄 변경" 뿐이고 둘 다 Home·Schedule 화면 소관이다). 그래서
/// `roleCapabilitiesProvider` 를 참조하지 않는다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const AppHeader(title: '설정'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          children: [
            const Text('알림', style: BaraedaTypography.h3),
            const SizedBox(height: BaraedaSpacing.space2),
            const NotificationSettingsPanel(),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            const Text('단말', style: BaraedaTypography.h3),
            const SizedBox(height: BaraedaSpacing.space2),
            const DeviceRegistrationPanel(),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            const Text('계정', style: BaraedaTypography.h3),
            const SizedBox(height: BaraedaSpacing.space2),
            BaraedaButton(
              label: '비밀번호 변경',
              variant: BaraedaButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.passwordChange),
            ),
            const SizedBox(height: BaraedaSpacing.space2),
            // 로그아웃(2026-09-23 · LO 2026-09-26 확인 대화 추가) — 역할이
            // 비면 라우터가 로그인 화면으로 보낸다. 되돌릴 수 없는 동작이라
            // 확인 대화 1회를 거친다(승인 대기 화면의 로그아웃은 이 대화가
            // 없다 — 그 화면은 `active` 갈래가 아니라 이번 범위 밖).
            BaraedaButton(
              label: '로그아웃',
              variant: BaraedaButtonVariant.ghost,
              onPressed: () => _confirmLogout(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// 확인 대화 1회 → 확정 시 [signOut] 재사용. 실패해도 [signOut] 자체가
/// 역할·상태를 비운다(그 함수 문서 참고) — 여기서 에러를 따로 처리하지
/// 않는다.
Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('로그아웃'),
      content: const Text('로그아웃 하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('로그아웃하기'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    // [signOut] 은 요청이 실패해도 `finally` 로 역할·상태를 비운 뒤 원래
    // 예외를 다시 던진다(그 함수 문서 참고) — 사용자에게는 이미 로그인
    // 화면으로 넘어가는 결과가 같으므로 여기서 삼킨다. 그렇지 않으면
    // 이 화면(호출자가 없는 버튼 콜백)에서 처리되지 않은 예외로 남는다.
    try {
      await signOut(ref);
    } on Failure {
      // 이미 로그아웃 처리됐다 — 위 주석 참고.
    }
  }
}
