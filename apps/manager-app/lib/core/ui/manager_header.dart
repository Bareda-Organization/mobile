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
    this.strip,
  });

  final String title;
  final String? subtitle;
  final bool dateSubtitle;
  final bool showSos;

  /// 홈 탭만 넘긴다 — 회차를 아직 고르지 않은 화면에서 신고할 회차를 찾는 데 쓴다([EmergencyButton]).
  final List<ManagerRun>? homeRuns;
  final VoidCallback? onBack;

  /// 머리줄 **위**에 붙는 한 줄 띠(시안 `.m-strip` — 연결 끊김
  /// `BaraedaConnectionStrip`). 상태 표시줄은 띠가 비키고 머리줄은 그 아래에서
  /// 시작한다. 없으면 예전과 같다.
  final Widget? strip;

  /// 띠 한 줄의 높이 — `BaraedaConnectionStrip` 의 최소 높이(40)와 같다.
  static const double stripHeight = 40;

  @override
  Size get preferredSize => Size.fromHeight(
    BaraedaSpacing.headerHeight +
        (subtitle != null || dateSubtitle ? 8 : 0) +
        (strip == null ? 0 : stripHeight),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = AppHeader(
      title: title,
      subtitle: dateSubtitle
          ? ref.watch(managerHeaderSubtitleProvider)
          : subtitle,
      onBack: onBack,
      tone: AppHeaderTone.plain,
      actions: showSos ? EmergencyButton(homeRuns: homeRuns) : null,
    );
    final hasSubtitle = subtitle != null || dateSubtitle;
    // 머리줄 높이는 고정이다(제목만 56, 부제까지 64) — 공용 머리줄이 글자를 늘리는 한도(부제 있으면 1.1배, 없으면
    // 1.6배)까지 가면 반올림으로 1px 넘친다(시험으로 확인). 그래서 부제가 있으면 1.0배, 없으면 1.5배로 묶는다.
    // 제목 · 부제는 한 줄 `…` 이고 전체 내용은 본문에 다시 나온다.
    // 글자 배율 묶음은 **안쪽 context** 에서 읽는다 — 바깥 context 의 MediaQuery 를 복사하면 아래에서 지운 상태 표시줄
    // 여백(`removePadding`)이 되살아나 머리줄이 같은 여백을 두 번 비킨다.
    final scaled = Builder(
      builder: (inner) => MediaQuery(
        data: MediaQuery.of(inner).copyWith(
          textScaler: MediaQuery.textScalerOf(inner)
              .clamp(maxScaleFactor: hasSubtitle ? 1 : 1.5),
        ),
        child: header,
      ),
    );
    final stripWidget = strip;
    if (stripWidget == null) return scaled;
    // 띠가 상태 표시줄 아래를 차지하므로 머리줄은 안전 영역(위)을 다시 비키지 않는다. 띠 글자는 한 줄 높이를 넘지
    // 않게 1.3배로 묶는다.
    return Column(
      children: [
        ColoredBox(
          color: context.colors.bgBase,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: stripHeight,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.3),
                ),
                child: stripWidget,
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: scaled,
          ),
        ),
      ],
    );
  }
}
