import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// 매니저 앱 머리줄 — 제목 + 부제 한 줄 + 오른쪽 비상 단추(시안 `.m-appbar`).
///
/// [subtitle] 을 비우고 [dateSubtitle] 을 켜면 `10월 3일 (토) · 학원 · 기사 이름` 이 부제가 된다(탭
/// 화면).
/// 비상 단추는 기사·동승자 모두 로그인 뒤 모든 화면 머리줄에 둔다(M-15) — 로그인 · 가입 · 차단 같은
/// 로그인 전 화면은 [showSos] 를 끈다. 뒤로 가기는 뒤에 화면이 있을 때만 [AppHeader] 가 그린다.
class ManagerHeader extends ConsumerWidget implements PreferredSizeWidget {
  const new({
    required this.title,
    super.key,
    this.subtitle,
    this.dateSubtitle = false,
    this.showSos = true,
    this.homeRuns,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final bool dateSubtitle;
  final bool showSos;

  /// 홈 탭만 넘긴다 — 회차를 아직 고르지 않은 화면에서 신고할 회차를 찾는 데 쓴다([EmergencyButton]).
  final List<ManagerRun>? homeRuns;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => Size.fromHeight(
    BaraedaSpacing.headerHeight + (subtitle != null || dateSubtitle ? 8 : 0),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppHeader(
      title: title,
      subtitle: dateSubtitle
          ? ref.watch(managerHeaderSubtitleProvider)
          : subtitle,
      onBack: onBack,
      tone: AppHeaderTone.plain,
      actions: showSos ? EmergencyButton(homeRuns: homeRuns) : null,
    );
  }
}
