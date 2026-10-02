import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/router.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/network/offline_bar.dart';

/// 학부모·학생 앱 진입점. 라이트 기본이며 `ThemeMode.system` 은 쓰지 않는다
/// — 다크는 야간 하원 화면·매니저 앱 전용(CONVENTIONS_FLUTTER.md §3).
///
/// `authBootstrapProvider` 가 끝날 때까지는 라우터를 만들지 않는다 —
/// 자동 로그인(목표 표 5항) 판정 전에 `redirect` 가 먼저 돌면 저장된
/// refresh 토큰이 있어도 한 프레임 로그인 화면이 먼저 그려진다.
class BaraedaParentApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authBootstrapProvider);

    if (bootstrap.isLoading) {
      return MaterialApp(
        title: '바래다',
        debugShowCheckedModeBanner: false,
        theme: BaraedaTheme.light(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (bootstrap.hasError) {
      return MaterialApp(
        title: '바래다',
        debugShowCheckedModeBanner: false,
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WordWrapText('네트워크 상태를 확인해 주세요'),
                  const SizedBox(height: BaraedaSpacing.space4),
                  BaraedaButton(
                    label: '다시 시도',
                    onPressed: () => ref.invalidate(authBootstrapProvider),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '바래다',
      debugShowCheckedModeBanner: false,
      theme: BaraedaTheme.light(),
      darkTheme: BaraedaTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      // 연결이 끊기면 어느 화면이든 맨 위에 한 줄(R46 B2 #22). 표시줄이 상태 표시줄 여백을 이미 차지했으므로
      // 아래 화면은 위쪽 여백을 한 번 더 비우지 않게 걷어 낸다.
      builder: (context, child) => _OfflineFrame(child: child),
    );
  }
}

/// 앱 전체를 감싸 끊김 한 줄을 맨 위에 붙이는 틀.
class _OfflineFrame extends ConsumerWidget {
  const new({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(
      networkStatusProvider.select((status) => status.isOffline),
    );
    final body = child ?? const SizedBox.shrink();
    if (!isOffline) return body;
    return Column(
      children: [
        const OfflineBar(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: body,
          ),
        ),
      ],
    );
  }
}
