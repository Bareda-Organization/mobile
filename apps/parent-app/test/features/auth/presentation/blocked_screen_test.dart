import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/features/auth/presentation/blocked_screen.dart';

class _MemoryContactStorage extends AcademyContactStorage {
  new(this.value);

  final String? value;

  @override
  Future<String?> read() async => value;
}

Future<void> _pump(WidgetTester tester, {String? saved}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        academyContactStorageProvider.overrideWithValue(
          _MemoryContactStorage(saved),
        ),
      ],
      child: const MaterialApp(home: BlockedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// R32 P13 — 차단 안내가 "학원 관리자(메인 관리자)" 처럼 두 역할을 섞어, 사용자가 누구에게
/// 물어야 하는지 알 수 없었다. 문의처는 학원 하나로 적는다(UF-X-04 · Ruling 329).
/// R48 `Ruling 825` — 차단 화면의 학원 전화는 기기에 저장한 마지막 학원 문의처이고, 없으면 문장만 둔다.
void main() {
  testWidgets('차단 안내의 문의처는 학원 하나이고 관리자 역할 이름을 섞지 않는다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('학원에 문의해 주세요'), findsOneWidget);
    expect(find.textContaining('메인 관리자'), findsNothing);
    expect(find.textContaining('학원 관리자'), findsNothing);
  });

  // L5 — 잠금은 메인 관리자만 풀 수 있다(AUTH-06 · C-11). "학원이 잠금을 풀면" 은 푸는 주체를 학원으로 단정한다.
  testWidgets('L5 잠금을 누가 푸는지 단정하지 않는다 — 문의처만 학원이다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('학원이 잠금'), findsNothing);
    expect(find.text('잠금이 풀리면 바로 다시 로그인할 수 있어요.'), findsOneWidget);
  });

  testWidgets('저장한 학원 문의처에 번호가 있으면 "학원에 전화 · 번호" 가 주 단추다', (tester) async {
    await _pump(tester, saved: '하늘수학 부천중동점 032-000-1100');

    expect(find.text('학원에 전화 · 032-000-1100'), findsOneWidget);
    final call = tester.widget<BaraedaButton>(
      find.widgetWithText(BaraedaButton, '학원에 전화 · 032-000-1100'),
    );
    expect(call.variant, BaraedaButtonVariant.primary);
    expect(call.onPressed, isNotNull);
  });

  testWidgets('저장한 문의처가 없으면 전화 단추 없이 "다니는 학원에 문의해 주세요" 문장만 있다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('학원에 전화'), findsNothing);
    expect(find.textContaining('다니는 학원에 문의해 주세요'), findsOneWidget);
  });

  testWidgets('문의처가 번호 모양이 아닌 글자뿐이면 전화 단추를 그리지 않는다(Ruling 827)', (
    tester,
  ) async {
    await _pump(tester, saved: '방문 문의 환영');

    expect(find.textContaining('학원에 전화'), findsNothing);
  });

  test('번호 모양 뽑기 — 하이픈 · 대표번호 · 붙여 쓴 번호', () {
    expect(phoneNumberOf('문의 032-000-1100 (평일)'), '032-000-1100');
    expect(phoneNumberOf('1588-1234'), '1588-1234');
    expect(phoneNumberOf('0320001100'), '0320001100');
    expect(phoneNumberOf('방문 문의 환영'), isNull);
    expect(phoneNumberOf(null), isNull);
  });
}
