import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/features/settings/presentation/widgets/notification_settings_panel.dart';

/// 설정 화면 — P-09 (IMPLEMENTATION_PLAN.md §3.1, §3.14 · §2.11 · §2.8).
///
/// UF-S-01 확인 결과 이 화면은 역할별로 감출 항목이 없다 — 학생 계정도
/// 알림 설정(S-03)에 그대로 접근한다(학생에게 감추는 것은 "탑승 토글·
/// 일일 스케줄 변경" 뿐이고 둘 다 Home·Schedule 화면 소관이다). 그래서
/// `roleCapabilitiesProvider` 를 참조하지 않는다.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
    );
  }
}
