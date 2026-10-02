import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';

class _FixedClock implements Clock {
  const new(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

/// 주어진 상태로 고정된 링크 — 칩이 받은 상태를 어떻게 그리는지만 본다.
class _FixedLink extends PositionLinkNotifier {
  new(this._link);
  final PositionLink _link;
  @override
  PositionLink build() => _link;
}

void main() {
  final now = DateTime(2026, 10, 1, 8);
  DateTime ago(int seconds) => now.subtract(Duration(seconds: seconds));

  group('judgePositionLink — 마지막 성공 전송 시각으로 세 상태를 가른다', () {
    PositionLinkStatus judge({int? sentAgo, int startedAgo = 100}) =>
        judgePositionLink(
          now: now,
          link: PositionLink(
            startedAt: ago(startedAgo),
            lastSentAt: sentAgo == null ? null : ago(sentAgo),
          ),
        )!;

    test('6초 이내면 정상, 넘으면 지연, 30초가 되면 전송 안 됨', () {
      expect(judge(sentAgo: 0).kind, PositionLinkKind.normal);
      expect(judge(sentAgo: 6).kind, PositionLinkKind.normal);
      expect(judge(sentAgo: 7).kind, PositionLinkKind.delayed);
      expect(judge(sentAgo: 7).secondsSinceSent, 7);
      expect(judge(sentAgo: 29).kind, PositionLinkKind.delayed);
      expect(judge(sentAgo: 30).kind, PositionLinkKind.lost);
    });

    test('한 번도 성공하지 못했으면 송신 시작 시각부터 센다', () {
      expect(judge(startedAgo: 3).kind, PositionLinkKind.normal);
      expect(judge(startedAgo: 12).kind, PositionLinkKind.delayed);
      expect(judge(startedAgo: 12).secondsSinceSent, isNull);
      expect(judge(startedAgo: 45).kind, PositionLinkKind.lost);
    });

    test('송신 중이 아니면(startedAt 없음) 판정하지 않는다', () {
      expect(
        judgePositionLink(now: now, link: const PositionLink()),
        isNull,
      );
    });
  });

  group('PositionLinkChip', () {
    Future<void> pumpChip(WidgetTester tester, PositionLink link) =>
        tester.pumpWidget(
          ProviderScope(
            // 상태마다 새 컨테이너 — 같은 트리에서 override 만 바꿔 다시 그리면 앞 notifier 가 남는다.
            key: UniqueKey(),
            overrides: [
              clockProvider.overrideWithValue(_FixedClock(now)),
              positionLinkProvider.overrideWith(() => _FixedLink(link)),
            ],
            child: const MaterialApp(
              home: Scaffold(body: PositionLinkChip()),
            ),
          ),
        );

    testWidgets('정상 · 지연(N초 전 마지막 전송) · 전송 안 됨을 문구로 보여준다', (tester) async {
      await pumpChip(
        tester,
        PositionLink(startedAt: ago(100), lastSentAt: ago(2)),
      );
      expect(find.text('위치 전송 중'), findsOneWidget);

      await pumpChip(
        tester,
        PositionLink(startedAt: ago(100), lastSentAt: ago(15)),
      );
      expect(find.text('위치 전송 지연 · 15초 전 마지막 전송'), findsOneWidget);

      await pumpChip(
        tester,
        PositionLink(startedAt: ago(100), lastSentAt: ago(75)),
      );
      expect(find.text('위치 전송 안 됨 · 1분 15초 전 마지막 전송'), findsOneWidget);
    });

    testWidgets('송신 중이 아니면 아무것도 그리지 않는다', (tester) async {
      await pumpChip(tester, const PositionLink());
      expect(find.byType(Text), findsNothing);
    });
  });
}
