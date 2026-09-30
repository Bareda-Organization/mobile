/// 바래다 공용 위젯 패키지 — 앱은 이 파일 하나만 import 한다.
///
/// `apps/parent-app` · `apps/manager-app` 가 이 패키지에 의존해 디자인 토큰과
/// 테마, 공용 위젯을 공유한다. 구조는 `CONVENTIONS_FLUTTER.md §3` 를 따른다.
library;

// 테마 — ThemeData 라이트/다크 + 의미 색 ThemeExtension.
export 'theme/baraeda_colors.dart';
export 'theme/baraeda_theme.dart';
// 토큰 — 색 · 타입 · 여백 · 모양 · 모션.
export 'tokens/colors.dart';
export 'tokens/motion.dart';
export 'tokens/shape.dart';
export 'tokens/spacing.dart';
export 'tokens/typography.dart';
// 위젯 — 디자인 시스템 components/ 의 Dart 구현.
// 앱이 쓰지 않는 위젯은 두지 않는다(Ruling 405).
export 'widgets/core/core.dart';
export 'widgets/dev/dev_quick_login.dart';
export 'widgets/feedback/feedback.dart';
export 'widgets/forms/forms.dart';
export 'widgets/navigation/navigation.dart';
export 'widgets/transit/transit.dart';
