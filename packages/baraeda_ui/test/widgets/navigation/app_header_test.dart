// [AppHeader] 시험 — `Scaffold.appBar` 자리에 놓였을 때 상태 표시줄을 비켜서는가.
//
// ⚠ 이 검사가 0건이어서 결함이 살아남았다. 2026-09-20 iPhone 17 Pro 시뮬레이터에서
// 학부모 앱 홈의 제목 "오늘 운행" 이 상태 표시줄 시계와 **겹쳐 그려졌다.**
// Material `AppBar` 는 안쪽에서 안전 영역을 처리하지만, 직접 만든
// `PreferredSizeWidget` 은 그 일을 스스로 해야 한다.
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/navigation/app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 상태 표시줄이 있는 기기를 흉내 낸다 — `padding.top` 이 0 이면 이 결함이 재현되지 않는다.
  Widget wrap(Widget header, {double statusBar = 59}) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(top: statusBar)),
        child: Scaffold(appBar: header as PreferredSizeWidget, body: const SizedBox()),
      ),
    );
  }

  testWidgets('제목이 상태 표시줄 아래에서 시작한다', (tester) async {
    await tester.pumpWidget(wrap(const AppHeader(title: '오늘 운행')));

    final top = tester.getTopLeft(find.text('오늘 운행')).dy;
    expect(
      top,
      greaterThanOrEqualTo(59),
      reason: '제목이 상태 표시줄(59) 안쪽에서 시작하면 시계·배터리와 겹쳐 그려진다',
    );
  });

  testWidgets('뒤로 버튼도 상태 표시줄 아래에 있다', (tester) async {
    await tester.pumpWidget(wrap(AppHeader(title: '노선', onBack: () {})));

    final top = tester.getTopLeft(find.byTooltip('뒤로')).dy;
    expect(top, greaterThanOrEqualTo(59),
        reason: '제목만 내리고 버튼을 두면 같은 줄이 어긋난다');
  });

  testWidgets('상태 표시줄이 없는 기기에서는 여백을 더하지 않는다', (tester) async {
    await tester.pumpWidget(wrap(const AppHeader(title: '오늘 운행'), statusBar: 0));

    expect(tester.getTopLeft(find.text('오늘 운행')).dy, lessThan(56),
        reason: '고정값을 더하면 여백이 없는 기기에서 머리말이 쓸데없이 두꺼워진다');
  });
}
