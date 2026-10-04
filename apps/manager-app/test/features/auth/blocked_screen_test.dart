import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/features/auth/presentation/blocked_screen.dart';

import '../../support/fake_academy_contact_store.dart';

/// `Ruling 825` — 잠긴 계정은 서버에서 학원 번호를 받을 수 없다. 차단 화면의 전화 번호는 이 기기가 마지막 로그인
/// 성공에서 저장해 둔 값이고, 없거나 번호 모양이 아니면 전화 단추 대신 안내 문장을 보인다.
void main() {
  Future<List<Uri>> pump(WidgetTester tester, String? saved) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(saved),
          ),
          uriOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(home: BlockedScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('저장된 학원 번호가 있으면 [학원에 전화 · 번호] 가 그 번호로 전화를 건다', (tester) async {
    final opened = await pump(tester, '032-000-1100');

    expect(find.text('학원에 전화 · 032-000-1100'), findsOneWidget);
    expect(find.text('다니는 학원에 문의해 주세요'), findsNothing);

    await tester.tap(
      find.widgetWithText(BaraedaButton, '학원에 전화 · 032-000-1100'),
    );
    await tester.pumpAndSettle();

    expect(opened, [Uri(scheme: 'tel', path: '032-000-1100')]);
  });

  testWidgets('저장된 번호가 없으면 전화 단추 없이 "다니는 학원에 문의해 주세요" 를 보인다', (tester) async {
    await pump(tester, null);

    expect(find.text('다니는 학원에 문의해 주세요'), findsOneWidget);
    expect(find.textContaining('학원에 전화'), findsNothing);
  });

  testWidgets('번호 모양이 아닌 연락처(문장)는 걸 곳이 없어 안내 문장으로 대신한다', (tester) async {
    await pump(tester, '평일 오전 9시부터 6시까지');

    expect(find.text('다니는 학원에 문의해 주세요'), findsOneWidget);
    expect(find.textContaining('학원에 전화'), findsNothing);
  });

  testWidgets('저장소는 새 번호로 덮고 빈 값으로는 지우지 않는다', (tester) async {
    final store = FakeAcademyContactStore('032-000-1100');
    await store.save('  ');
    await store.save(null);
    expect(await store.read(), '032-000-1100');
    await store.save('02-123-4567');
    expect(await store.read(), '02-123-4567');
  });
}
