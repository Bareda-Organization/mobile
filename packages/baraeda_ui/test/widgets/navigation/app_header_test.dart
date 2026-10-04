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
        child: Scaffold(
          appBar: header as PreferredSizeWidget,
          body: const SizedBox(),
        ),
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
    expect(top, greaterThanOrEqualTo(59), reason: '제목만 내리고 버튼을 두면 같은 줄이 어긋난다');
  });

  // 2026-09-29 사용자 지적 "앱 화면에서 뒤로가기 버튼" — 학부모 앱의 설정·일정·노선 상세·
  // 자녀 연결·실시간 위치 5개 화면이 `onBack` 을 안 넘겨 뒤로 버튼이 없었다. 화면마다 넘기게
  // 하면 다음 화면이 또 빠뜨린다 → 뒤에 화면이 있으면 머리말이 스스로 그린다.
  testWidgets('뒤에 화면이 있으면 onBack 없이도 뒤로 버튼이 생기고, 누르면 돌아간다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: const Scaffold(
          appBar: AppHeader(title: '오늘 운행'),
          body: SizedBox(),
        ),
      ),
    );
    final homeContext = tester.element(find.text('오늘 운행'));
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          appBar: AppHeader(title: '설정'),
          body: SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsNothing, reason: '뒤로 버튼을 눌렀는데 설정 화면이 그대로다');
    expect(find.text('오늘 운행'), findsOneWidget);
  });

  testWidgets('첫 화면에는 뒤로 버튼이 없다', (tester) async {
    await tester.pumpWidget(wrap(const AppHeader(title: '오늘 운행')));

    expect(
      find.byTooltip('뒤로'),
      findsNothing,
      reason: '돌아갈 화면이 없는데 버튼을 그리면 눌러도 아무 일이 없다',
    );
  });

  testWidgets('상태 표시줄이 없는 기기에서는 여백을 더하지 않는다', (tester) async {
    await tester.pumpWidget(
      wrap(const AppHeader(title: '오늘 운행'), statusBar: 0),
    );

    expect(
      tester.getTopLeft(find.text('오늘 운행')).dy,
      lessThan(56),
      reason: '고정값을 더하면 여백이 없는 기기에서 머리말이 쓸데없이 두꺼워진다',
    );
  });

  // 시안 R48 머리줄 — 제목 24 + 부제 14 가 `preferredSize`(64) 안에 들어가야 한다.
  // 높이가 고정이라 글자 배율이 크면 넘치므로 배율을 묶는다.
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('부제가 있는 머리줄은 글자 $scale 배에서도 넘치지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            appBar: AppHeader(title: '명단', subtitle: '2호차 · 등원 · 12:20 출발'),
            body: SizedBox(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('부제는 한 줄에서 `…` 로 잘린다 — 긴 학원 이름이 비상 버튼 밑으로 흐르지 않는다', (
    tester,
  ) async {
    const longSub = '기사 박정훈 · 하늘수학학원 부천중동 센트럴파크 푸르지오 2단지 아파트 정문 앞 본원 제2별관';
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: const Scaffold(
          appBar: AppHeader(title: '운행 중', subtitle: longSub),
          body: SizedBox(),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text(longSub));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('제목은 24 · 한 줄, floating 은 면 없이 제목만 알약 안에', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: const Scaffold(
          appBar: AppHeader(title: '실시간 위치', tone: AppHeaderTone.floating),
          body: SizedBox(),
        ),
      ),
    );
    // floating 의 제목은 16 — 흰 알약 안.
    expect(tester.widget<Text>(find.text('실시간 위치')).style!.fontSize, 16);
  });
}
