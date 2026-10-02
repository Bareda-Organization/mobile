import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/core/network/network_status.dart';

/// 연결이 끊겼을 때 화면 맨 위에 붙는 한 줄 — 홈에서 자녀·회차·알림 카드가 저마다 "불러오지 못했습니다" 를
/// 나열하던 것을 이 한 줄로 모은다(R46 B2 #22). 연결 중이면 아무것도 그리지 않는다.
class OfflineBar extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(
      networkStatusProvider.select((status) => status.isOffline),
    );
    if (!isOffline) return const SizedBox.shrink();

    final lastReachableAt = ref.read(networkStatusProvider).lastReachableAt;
    final text = lastReachableAt == null
        ? '네트워크 연결이 끊겼습니다'
        : '네트워크 연결이 끊겼습니다 · 마지막 갱신 '
              '${DateFormat('H:mm').format(lastReachableAt.toLocal())}';
    final colors = context.colors;
    // 앱 틀(MaterialApp.builder)은 Scaffold 밖이라 Material 도 배경도 없다 — 직접 가진다.
    // 안 그러면 글자에 노란 밑줄이 뜨고 상태 표시줄 영역이 검게 빈다.
    // 배경이 위쪽 안전 영역까지 칠해지도록 SafeArea 가 안쪽이다.
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: colors.statusMissedSoft,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BaraedaSpacing.gutterMobile,
                vertical: BaraedaSpacing.space2,
              ),
              child: WordWrapText(
                text,
                style: BaraedaTypography.bodySm.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
