// 단추의 꺼짐 · 이유 글 · 긴 이름 — 시안 kit "버튼 · 큰 주 버튼" · "UX 개선 부품"(C3 · M5).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double? width}) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width ?? 320, child: child),
    ),
  ),
);

Color _inkColor(WidgetTester tester) =>
    ((tester.widget<Ink>(find.byType(Ink)).decoration)! as BoxDecoration)
        .color!;

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  const colors = BaraedaColors.light;

  group('꺼진 단추는 누름 · 올림에 반응하지 않는다(C3)', () {
    testWidgets('꺼진 단추: 누르고 있어도 크기 · 색이 그대로이고 콜백은 없다', (tester) async {
      await tester.pumpWidget(
        _host(const BaraedaButton(label: '변경하기', block: true)),
      );
      final before = _inkColor(tester);
      expect(before, colors.disabledSurface);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('변경하기')),
      );
      await tester.pump(BaraedaDuration.press);
      expect(_scale(tester), 1);
      expect(_inkColor(tester), before);
      await gesture.up();
    });

    testWidgets('꺼진 단추의 글자색은 기존 보조 글자색(#5C665F) 이다', (tester) async {
      await tester.pumpWidget(
        _host(const BaraedaButton(label: '변경하기', block: true)),
      );
      final text = tester.widget<Text>(find.text('변경하기'));
      expect(text.style!.color, colors.disabledText);
      expect(colors.disabledText, const Color(0xFF5C665F));
    });

    testWidgets('꺼진 보조 단추도 테두리가 없다 — 켜진 것처럼 보이지 않게', (tester) async {
      await tester.pumpWidget(
        _host(
          const BaraedaButton(
            label: '확인',
            variant: BaraedaButtonVariant.secondary,
          ),
        ),
      );
      final decoration =
          tester.widget<Ink>(find.byType(Ink)).decoration! as BoxDecoration;
      expect(decoration.border, isNull);
      expect(decoration.color, colors.disabledSurface);
    });

    testWidgets('켜진 단추는 누르는 동안 0.97 배로 줄고 조금 어두워진다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(BaraedaButton(label: '확인', block: true, onPressed: () => taps++)),
      );
      final rest = _inkColor(tester);
      expect(_scale(tester), 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('확인')),
      );
      await tester.pump(BaraedaDuration.press);
      expect(_scale(tester), BaraedaMotionValue.pressScale);
      expect(_inkColor(tester), isNot(rest));

      await gesture.up();
      await tester.pump(BaraedaDuration.press);
      expect(_scale(tester), 1);
      expect(taps, 1);
    });

    testWidgets('움직임 줄이기가 켜지면 크기는 그대로, 색만 바뀐다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: BaraedaButton(label: '확인', block: true, onPressed: () {}),
            ),
          ),
        ),
      );
      final rest = _inkColor(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('확인')),
      );
      await tester.pump(BaraedaDuration.press);
      expect(_scale(tester), 1);
      expect(_inkColor(tester), isNot(rest));
      await gesture.up();
    });
  });

  group('꺼진 단추 아래 이유 글', () {
    testWidgets('꺼져 있으면 이유가 단추 아래에 보이고 낭독 힌트로도 실린다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const BaraedaButton(
            label: '변경하기',
            block: true,
            disabledReason: '새 비밀번호를 입력하면 눌러요',
          ),
        ),
      );
      final reason = find.text('새 비밀번호를 입력하면 눌러요');
      expect(reason, findsOneWidget);
      expect(
        tester.getTopLeft(reason).dy,
        greaterThan(tester.getBottomLeft(find.byType(Ink)).dy - 1),
      );
      expect(
        tester.getSemantics(find.byType(BaraedaButton)),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          label: '변경하기',
          hint: '새 비밀번호를 입력하면 눌러요',
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('켜지면 이유 글은 사라진다', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaButton(
            label: '변경하기',
            block: true,
            onPressed: () {},
            disabledReason: '새 비밀번호를 입력하면 눌러요',
          ),
        ),
      );
      expect(find.text('새 비밀번호를 입력하면 눌러요'), findsNothing);
    });
  });

  group('단추 안 긴 이름은 이름만 줄고 동사는 늘 보인다(M5)', () {
    const longName = '새솔초등학교 정문 건너편 버스정류장 앞 횡단보도 옆 아파트 단지 입구';

    testWidgets('좁은 폭에서 이름은 …로 줄고 `도착 처리` 는 잘리지 않는다', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaButton(
            label: '도착 처리',
            name: longName,
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () {},
          ),
          width: 300,
        ),
      );
      expect(tester.takeException(), isNull);

      final name = tester.widget<Text>(find.text(longName));
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.maxLines, 1);

      final verb = find.text('도착 처리');
      final button = find.byType(Ink);
      expect(
        tester.getRect(verb).right,
        lessThanOrEqualTo(tester.getRect(button).right),
      );
      expect(
        tester.getRect(verb).left,
        greaterThanOrEqualTo(tester.getRect(button).left),
      );
      // 동사 글자는 한 줄 · 줄임표 없이 그려진다.
      final verbText = tester.widget<Text>(verb);
      expect(verbText.overflow, isNot(TextOverflow.ellipsis));
      final paragraph = tester.renderObject<RenderParagraph>(verb);
      expect(paragraph.didExceedMaxLines, isFalse);
    });

    testWidgets('이름이 짧으면 이름 + 동사가 모두 보인다', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaButton(
            label: '도착 처리',
            name: '새솔초 정문',
            size: BaraedaButtonSize.xl,
            block: true,
            onPressed: () {},
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('새솔초 정문'),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(find.text('도착 처리'), findsOneWidget);
    });

    testWidgets('낭독은 이름과 동사를 이어 한 번 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          BaraedaButton(
            label: '도착 처리',
            name: '새솔초 정문',
            block: true,
            onPressed: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('새솔초 정문 도착 처리'), findsOneWidget);
      handle.dispose();
    });
  });

  group('크기 44 · 48 · 64', () {
    for (final (size, height) in [
      (BaraedaButtonSize.sm, 44.0),
      (BaraedaButtonSize.md, 48.0),
      (BaraedaButtonSize.xl, 64.0),
    ]) {
      testWidgets('${size.name} 높이는 $height', (tester) async {
        await tester.pumpWidget(
          _host(BaraedaButton(label: '확인', size: size, onPressed: () {})),
        );
        expect(tester.getSize(find.byType(Ink)).height, height);
      });
    }
  });
}
