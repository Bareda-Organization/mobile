import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/ui/manager_header.dart';

/// 실기기에는 상태 표시줄 여백(위 59pt)이 있다. 위젯 시험의 기본 화면은 그 여백이 0 이라, 띠가 붙은 머리줄이 그
/// 여백을 두 번 비켜 제목이 가려지는 결함이 시험에 드러나지 않았다(시뮬레이터 캡처에서 발견).
Widget _app({required Widget? strip}) => ProviderScope(
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: const EdgeInsets.only(top: 59)),
      child: child!,
    ),
    home: Scaffold(
      appBar: ManagerHeader(title: '명단', showSos: false, strip: strip),
      body: const SizedBox.shrink(),
    ),
  ),
);

void main() {
  testWidgets('띠가 있어도 제목이 띠 바로 아래 머리줄 안에 온전히 보인다', (tester) async {
    await tester.pumpWidget(
      _app(
        strip: const BaraedaConnectionStrip(
          state: BaraedaConnectionState.offline,
          message: '인터넷 연결 없음 · 08:41 부터',
        ),
      ),
    );

    final strip = tester.getRect(find.byType(BaraedaConnectionStrip));
    final title = tester.getRect(find.text('명단'));
    final header = tester.getRect(find.byType(ManagerHeader));

    expect(title.top, greaterThanOrEqualTo(strip.bottom), reason: '제목은 띠 아래');
    expect(
      title.bottom,
      lessThanOrEqualTo(header.bottom),
      reason: '제목이 머리줄 영역을 벗어나 가려지면 안 된다',
    );
  });

  testWidgets('띠가 없으면 예전처럼 상태 표시줄 아래에서 시작한다', (tester) async {
    await tester.pumpWidget(_app(strip: null));

    final title = tester.getRect(find.text('명단'));
    final header = tester.getRect(find.byType(ManagerHeader));

    expect(title.top, greaterThanOrEqualTo(59));
    expect(title.bottom, lessThanOrEqualTo(header.bottom));
  });
}
