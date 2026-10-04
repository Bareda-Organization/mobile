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
          origin: '중앙 집결지',
          destination: '바래다학원 A',
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

  // R46-LAST `Ruling 582`(R46-FUMGR `Ruling 573`) — 글자 2.0배에서 상태 알약 +
  // `호차 · 등원` 한 줄이 가로로 넘쳤다(360×640 에서 57px · 375×750 에서 42px,
  // 1.0·1.3배는 원래 넘치지 않음). 아래 세 크기를 모두 지킨다.
  // (실기기 release 는 글자 잘림 · debug 는 노란 띠로 보인다.)
  for (final scale in const [1.0, 1.3, 2.0]) {
    testWidgets('360 폭 · 글자 $scale배에서도 가로로 넘치지 않는다', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          // 매니저 앱 운행 화면이 넘기는 값 그대로, 화면 좌우 여백 안에 둔다.
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: BaraedaSpacing.gutterMobile,
              ),
              child: RunSummaryCard(
                bus: '3호차',
                leg: '등원',
                statusLabel: '운행 중',
                eta: '약 5분 후 도착합니다',
                origin: '송파 롯데월드타워 정문 앞 집결지',
                destination: '바래다학원 본원 지하 주차장 입구',
                manager: '김동승',
                driver: '박기사',
              ),
            ),
          ),
        ),
      );

      // 넘침은 그리는 동안 `RenderFlex overflowed` 로 보고된다 — 시험 바인딩이 받아 둔 것을 꺼낸다.
      expect(tester.takeException(), isNull);

      // 한 줄에 들어가는 글자 크기에서는 `호차 · 등원` 이 카드 안쪽 오른쪽 끝에 붙는다(예전 `Spacer` 배치).
      if (scale == 1.0) {
        final card = tester.getRect(find.byType(RunSummaryCard));
        final label = tester.getRect(find.text('3호차 · 등원'));
        expect(
          label.right,
          closeTo(card.right - BaraedaSpacing.space5, 0.5),
          reason: '`Wrap` 이 내용 너비로 줄어들면 오른쪽 끝에 붙지 않는다',
        );
      }
    });
  }
}
