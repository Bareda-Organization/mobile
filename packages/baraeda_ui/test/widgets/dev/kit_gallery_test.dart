// 부품 견본이 글자 크기 1.0 · 1.3 배에서 넘치지 않고 그려지는지 — 새 부품이 한 화면에서 같이 서는지 본다.
import 'package:baraeda_ui/widgets/dev/kit_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    for (final dark in [false, true]) {
      testWidgets('부품 견본 — 글자 $scale 배 · ${dark ? '다크' : '라이트'} 에서 넘침 없음', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: KitGallery(dark: dark),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        // 위쪽 절 · 중간 · 아래쪽 절을 지나가며 넘침이 없는지 본다.
        // 타임라인이 안쪽에 자기 ListView(스크롤 안 함)를 가져 첫 번째(바깥) 것만 민다.
        final list = find.byType(ListView).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(list, const Offset(0, -600));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
