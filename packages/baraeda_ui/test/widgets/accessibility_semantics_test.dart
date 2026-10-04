// F07-10 — 낭독 이중 출력 · 색으로만 전달되는 상태 · 버튼 역할 · 터치 영역 48.
// 동작은 `tester.getSemantics` 로 실제 시맨틱 트리를 읽어 판정한다(코드 읽기 추정이 아니다).
import 'dart:ui' show Tristate;

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: BaraedaTheme.light(),
    home: Scaffold(body: Center(child: child)),
  ),
);

/// 그 위젯 노드가 낭독기에 싣는 전체 문구.
String _labelOf(WidgetTester tester, Type type) =>
    tester.getSemantics(find.byType(type).first).label;

void main() {
  group('같은 문구를 두 번 읽지 않는다', () {
    // (위젯, 타입, 문구가 딱 한 번만 나와야 하는 핵심 단어들)
    final cases = <String, (Widget, Type, List<String>)>{
      'BaraedaStatusPill': (
        const BaraedaStatusPill(status: BaraedaStatus.boarded, label: '탑승 완료'),
        BaraedaStatusPill,
        ['탑승 완료'],
      ),
      'BaraedaBadge': (
        const BaraedaBadge(label: '대기', count: 3),
        BaraedaBadge,
        ['대기'],
      ),
      'AlertBanner': (
        const AlertBanner(tone: AlertTone.moving, title: '지연', body: '10분 늦음'),
        AlertBanner,
        ['지연', '10분'],
      ),
      'EmptyState': (
        const EmptyState(icon: 'bell', title: '알림 없음', body: '새 알림이 없음'),
        EmptyState,
        ['알림 없음', '새 알림'],
      ),
      'NotificationTile': (
        const NotificationTile(
          icon: 'clock',
          status: BaraedaStatus.moving,
          kindLabel: '지연',
          title: '늦어짐 안내',
          body: '서준',
          time: '8:58',
          timeSpoken: '오전 8시 58분',
        ),
        NotificationTile,
        ['늦어짐 안내', '서준', '지연', '오전 8시 58분'],
      ),
      'StatCard': (
        const StatCard(label: '탑승', value: '12', unit: '명', sub: '전체'),
        StatCard,
        ['탑승', '12', '전체'],
      ),
      // 이름 뒤 2자 이니셜('서준')도 낭독되면 '서준' 이 두 번 나온다.
      'StudentRow': (
        const StudentRow(name: '김서준', meta: '강남역'),
        StudentRow,
        ['서준', '강남역'],
      ),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, entry.value.$1);

        final label = _labelOf(tester, entry.value.$2);

        for (final word in entry.value.$3) {
          expect(
            word.allMatches(label).length,
            1,
            reason: '"$word" 이 한 번이 아니다: ${label.replaceAll('\n', ' | ')}',
          );
        }
        handle.dispose();
      });
    }

    testWidgets('StopTimeline 한 정류장', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StopTimeline(
          stops: [
            Stop(
              name: '강남역',
              address: '1번 출구',
              time: '8:58',
              state: StopState.current,
            ),
          ],
        ),
      );

      // 정류장 이름을 싣는 낭독 노드는 하나뿐이다(자식 Text 가 따로 읽히지 않는다).
      expect(find.bySemanticsLabel(RegExp('강남역')), findsOneWidget);
      handle.dispose();
    });
  });

  group('상태를 색이 아닌 말로도 전한다', () {
    testWidgets('StopTimeline 은 지남·지금·다음·이후·건너뜀·추가를 낭독 문구에 싣는다', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const StopTimeline(
          stops: [
            Stop(name: 'A역', state: StopState.done),
            Stop(name: 'B역', state: StopState.current),
            Stop(name: 'C역', state: StopState.next),
            Stop(name: 'D역'), // 기본 상태 = upcoming
            Stop(name: 'E역', state: StopState.skipped),
            Stop(name: 'F역', state: StopState.added),
          ],
        ),
      );

      expect(find.bySemanticsLabel(RegExp('A역.*지남')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('B역.*지금')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('C역.*다음')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('D역.*이후')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('E역.*건너뜀')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('F역.*추가')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('NotificationTile 은 안 읽음을 낭독 문구에 싣는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const NotificationTile(
          icon: 'log-in',
          status: BaraedaStatus.boarded,
          kindLabel: '승차',
          title: '승차',
          time: '8:37',
          timeSpoken: '오전 8시 37분',
          unread: true,
        ),
      );

      expect(find.bySemanticsLabel(RegExp('안 읽음')), findsWidgets);
      handle.dispose();
    });
  });

  group('BaraedaButton', () {
    testWidgets('낭독기에 버튼 역할과 활성 여부를 싣는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, BaraedaButton(label: '저장', onPressed: () {}));
      expect(
        tester.getSemantics(find.byType(BaraedaButton)),
        matchesSemantics(
          label: '저장',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await _pump(tester, const BaraedaButton(label: '저장'));
      final flags = tester
          .getSemantics(find.byType(BaraedaButton))
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isButton, isTrue);
      expect(flags.isEnabled, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('기본(md) 높이는 터치 최소 48 이상이다', (tester) async {
      await _pump(tester, BaraedaButton(label: '저장', onPressed: () {}));

      expect(
        tester.getSize(find.byType(BaraedaButton)).height,
        greaterThanOrEqualTo(BaraedaSpacing.tapMin),
      );
    });
  });

  testWidgets('BaraedaIconButton 기본 크기는 터치 최소 48 이상이다', (tester) async {
    await _pump(
      tester,
      BaraedaIconButton(icon: 'bell', label: '알림 열기', onPressed: () {}),
    );

    final size = tester.getSize(find.byType(BaraedaIconButton));
    expect(size.shortestSide, greaterThanOrEqualTo(BaraedaSpacing.tapMin));
  });

  testWidgets('StudentRow 보호자 전화 버튼은 터치 최소 48 이상이다', (tester) async {
    await _pump(
      tester,
      StudentRow(name: '김서준', phone: '010-0000-0000', onCall: () {}),
    );

    // 행 전체(첫 InkWell)가 아니라 전화 버튼(마지막 InkWell)의 크기.
    final size = tester.getSize(find.byType(InkWell).last);
    expect(size.shortestSide, greaterThanOrEqualTo(BaraedaSpacing.tapMin));
  });
}
