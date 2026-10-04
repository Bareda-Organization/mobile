import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/features/live_map/presentation/trip_text.dart';

/// R49 `Ruling 832` — 실시간 위치 · 종료 문구의 도착지 이름. 등원은 학원 이름(`/me` 의 `academy.name`),
/// 하원은 내 승하차지 이름. 이름을 못 얻으면 R48 의 이름 없는 문구로 떨어진다.
void main() {
  group('tripDestination — 어느 쪽 이름이 도착지인가', () {
    test('등원은 학원 이름이다', () {
      expect(
        tripDestination(
          direction: RunDirection.toAcademy,
          academyName: '하늘수학',
          myStopName: '행복마을 입구',
        ),
        '하늘수학',
      );
    });

    test('하원은 내 승하차지 이름이다', () {
      expect(
        tripDestination(
          direction: RunDirection.fromAcademy,
          academyName: '하늘수학',
          myStopName: '행복마을 입구',
        ),
        '행복마을 입구',
      );
    });

    test('등원인데 학원 이름을 못 얻으면 하원 쪽 이름으로 채우지 않고 비운다', () {
      expect(
        tripDestination(
          direction: RunDirection.toAcademy,
          academyName: null,
          myStopName: '행복마을 입구',
        ),
        isNull,
      );
    });

    test('방향을 모르면(회차 목록 실패) 어느 이름도 고르지 않는다', () {
      expect(
        tripDestination(
          direction: null,
          academyName: '하늘수학',
          myStopName: '행복마을 입구',
        ),
        isNull,
      );
    });
  });

  group('sheetSubtitle — 시트 이름 아래 줄', () {
    final startedAt = DateTime(2026, 10, 5, 12, 5);

    test('운행 중에는 "도착지 가는 길 · 시각 운행 시작" 이다', () {
      expect(
        sheetSubtitle(ended: false, destination: '하늘수학', startedAt: startedAt),
        '하늘수학 가는 길 · 12:05 운행 시작',
      );
    });

    test('종료에는 "도착지 도착" 이고 시작 시각은 붙이지 않는다', () {
      expect(
        sheetSubtitle(ended: true, destination: '하늘수학', startedAt: startedAt),
        '하늘수학 도착',
      );
    });

    test('이름이 없으면 운행 중에는 "시각 운행 시작" 만 남는다', () {
      expect(
        sheetSubtitle(ended: false, destination: null, startedAt: startedAt),
        '12:05 운행 시작',
      );
    });

    test('이름이 없는 종료는 줄이 없다', () {
      expect(
        sheetSubtitle(ended: true, destination: null, startedAt: startedAt),
        isNull,
      );
    });

    test('시작 시각을 모르면 이름만 남고, 둘 다 없으면 줄이 없다', () {
      expect(
        sheetSubtitle(ended: false, destination: '하늘수학', startedAt: null),
        '하늘수학 가는 길',
      );
      expect(
        sheetSubtitle(ended: false, destination: null, startedAt: null),
        isNull,
      );
    });
  });

  group('endedBody — 종료 띠 본문', () {
    final finishedAt = DateTime(2026, 10, 5, 12, 52);

    test('이름이 있으면 "시각 도착지에 도착했어요." 다', () {
      expect(
        endedBody(finishedAt: finishedAt, destination: '하늘수학'),
        '12:52 하늘수학에 도착했어요.',
      );
    });

    test('이름이 없으면 R48 문구 "시각 에 운행을 마쳤어요." 로 떨어진다', () {
      expect(
        endedBody(finishedAt: finishedAt, destination: null),
        '12:52 에 운행을 마쳤어요.',
      );
    });

    test('종료 시각을 모르면 이름만 있어도 시각 없이 쓰고, 둘 다 없으면 본문이 없다', () {
      expect(endedBody(finishedAt: null, destination: '하늘수학'), '하늘수학에 도착했어요.');
      expect(endedBody(finishedAt: null, destination: null), isNull);
    });
  });
}
