import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/navigation/data/kakao_navi_launcher.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';

/// 외부 내비를 연 결과 — 화면이 문구로 옮긴다. 셋 다 비어 있으면 잘 열렸다.
class NavigationOpenResult {
  const new({this.truncatedNotice, this.notInstalled = false, this.error});

  /// 상한 때문에 앞 몇 곳만 넘겼다는 서버 안내.
  final String? truncatedNotice;

  /// 카카오내비 앱이 없다 — [설치하기] 를 붙인다.
  final bool notInstalled;

  /// 열지 못했다 — 화면에 그대로 보일 문구.
  final String? error;
}

/// 서버가 정한 [scope] 범위의 경로(§4.16)를 카카오내비로 넘긴다(RUN-08). 카카오내비는 공식 SDK 가 연다 —
/// 서버는 딥링크를 만들지 않는다. 운행 준비(`카카오내비로 길 확인`)와 운행 중(지도 위 [다음 목적지] · [남은 전 구간])이 같이 쓴다.
Future<NavigationOpenResult> openExternalNavigation(
  WidgetRef ref, {
  required String runId,
  required NavigationScope scope,
}) async {
  try {
    final route = await ref
        .read(navigationRepositoryProvider)
        .fetch(runId, scope);
    // 서버가 정한 공급자가 카카오가 아니면(티맵 등) 이 앱은 열 수 없다.
    final result = route.provider == 'kakao'
        ? await ref.read(kakaoNaviLauncherProvider).launch(route)
        : NaviLaunchResult.failed;
    return switch (result) {
      NaviLaunchResult.launched => NavigationOpenResult(
        truncatedNotice: route.truncated
            ? route.truncatedReason ?? '남은 승하차지가 많아 앞쪽만 내비에 넘겼어요'
            : null,
      ),
      NaviLaunchResult.notInstalled => const NavigationOpenResult(
        notInstalled: true,
      ),
      NaviLaunchResult.failed => const NavigationOpenResult(
        error: '카카오내비를 열지 못했어요 — 잠시 뒤 다시 시도해 주세요',
      ),
    };
  } on Failure catch (failure) {
    return NavigationOpenResult(error: describeFailure(failure));
  }
}
