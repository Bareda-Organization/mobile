import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/router.dart';
import 'package:manager_app/core/auth/account_session.dart';

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
    return MaterialApp.router(
      title: '바래다 매니저',
      debugShowCheckedModeBanner: false,
      theme: BaraedaTheme.dark(),
      darkTheme: BaraedaTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
