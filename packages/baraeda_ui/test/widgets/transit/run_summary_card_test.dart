// [RunSummaryCard] 시험 — **라벨이 값의 뜻과 맞는가**.
//
// ⚠ 2026-09-21 시뮬레이터 실측: 매니저 앱 홈이 `/manager/runs` 의 `origin`·`destination`
// (= 출발지·도착지, `API_SPEC §4.1`)을 넘기는데 카드는 그것을 **"현재 이동 중"·"다음 정류장"**
// 으로 적고 있었다. 출발 **전**인 회차(`확정 전`, 12:00)에도 "현재 이동 중" 이 떠서, 아직
// 아무 데도 안 간 버스가 움직이는 것처럼 보였다.
//
// 용어도 어긋났다 — 이 서비스에는 **공용 정류장 개념이 부재**하고 단위는 **승하차지**다
// (`FEATURE_SPEC C-12` · `PRD §6`). "정류장" 은 구 기획에서 뒤집힌 말이다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: BaraedaTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('출발지·도착지를 그 뜻대로 적는다 — 진행 상태로 적지 않는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RunSummaryCard(
          bus: '1호차',
          leg: '등원',
          status: BaraedaStatus.idle,
          statusLabel: '확정 전',
          eta: '12:00',
          currentStop: '중앙 집결지',
          nextStop: '바래다학원 A',
        ),
      ),
    );

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);

    // 출발 전인 회차에 "현재 이동 중" 이 뜨면 아직 안 간 버스가 움직이는 것으로 보인다.
    expect(find.text('현재 이동 중'), findsNothing);
    // 이 서비스에 공용 정류장 개념은 부재하다(C-12).
    expect(find.text('다음 정류장'), findsNothing);
  });
}
