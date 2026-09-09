import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/router.dart';

/// 기사·동승자 앱 진입점. **다크 고정** — `ThemeMode.system`·`.light` 은 쓰지
/// 않는다(CONVENTIONS_FLUTTER.md §3, 운행 시간대 특성).
class BaraedaManagerApp extends ConsumerWidget {
  const BaraedaManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
