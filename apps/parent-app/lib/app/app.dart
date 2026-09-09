import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/router.dart';

/// 학부모·학생 앱 진입점. 라이트 기본이며 `ThemeMode.system` 은 쓰지 않는다
/// — 다크는 야간 하원 화면·매니저 앱 전용(CONVENTIONS_FLUTTER.md §3).
class BaraedaParentApp extends ConsumerWidget {
  const BaraedaParentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '바래다',
      debugShowCheckedModeBanner: false,
      theme: BaraedaTheme.light(),
      darkTheme: BaraedaTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
