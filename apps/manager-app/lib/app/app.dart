import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/router.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_auto_sync.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

/// 기사·동승자 앱 진입점. **다크 고정** — `ThemeMode.system`·`.light` 은 쓰지
/// 않는다(CONVENTIONS_FLUTTER.md §3, 운행 시간대 특성).
///
/// `authBootstrapProvider` 가 끝날 때까지는 라우터를 만들지 않는다 —
/// 자동 로그인(목표 표 5항) 판정 전에 `redirect` 가 먼저 돌면 저장된
/// refresh 토큰이 있어도 한 프레임 로그인 화면이 먼저 그려진다
/// (`parent_app` 과 같은 이유).
class BaraedaManagerApp extends ConsumerWidget {
  const BaraedaManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authBootstrapProvider);
    // 위치 송신은 화면이 아니라 앱 전역이다(R33 M1) — 어느 화면에 있든 돌도록 앱 루트가 붙든다.
    // 송신 좌표가 바뀔 때마다 앱 전체가 다시 그려지지 않게 값은 읽지 않는다.
    ref.watch(positionTransmitterProvider.select((_) => null));

    if (bootstrap.isLoading) {
      return MaterialApp(
        title: '바래다 매니저',
        debugShowCheckedModeBanner: false,
        theme: BaraedaTheme.dark(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    // 로그인 이후 트리 전체를 감싼다 — 오프라인 큐 재생은 어느 화면에 있든
    // 돌아야 한다(M-06 "복구 시 자동 동기화"). 로딩 분기에는 붙이지 않는다:
    // 그때는 아직 토큰 판정 전이라 재생할 수 없다.
    return OfflineQueueAutoSync(
      child: MaterialApp.router(
        title: '바래다 매니저',
        debugShowCheckedModeBanner: false,
        theme: BaraedaTheme.dark(),
        darkTheme: BaraedaTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: router,
      ),
    );
  }
}
