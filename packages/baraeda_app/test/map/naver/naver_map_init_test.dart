import 'package:baraeda_app/map/map_surface.dart';
import 'package:baraeda_app/map/naver/naver_map_init.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 지도 SDK 초기화 — 실패는 기억하지 않아 다음 시도가 다시 부르고, 초기화 예외는 앱이 켜 두면 화면의 지도 오류
/// 콜백(`onAuthFailed`)에 닿는다.
void main() {
  var calls = 0;
  final caught = <Object>[];

  setUp(() {
    calls = 0;
    caught.clear();
    NaverMapInit.resetForTest();
  });
  tearDown(NaverMapInit.resetForTest);

  Widget adapter({required bool reportInitFailure}) {
    return MaterialApp(
      home: MapSurface(
        camera: const MapCamera(lat: 37.5, lng: 127),
        options: MapSurfaceOptions(reportInitFailure: reportInitFailure),
        onAuthFailed: caught.add,
      ),
    );
  }

  test('초기화가 실패하면 기억하지 않고 다음 호출이 다시 시도한다', () async {
    NaverMapInit.initializer =
        ({required clientId, required onAuthFailed}) async {
          calls++;
          if (calls == 1) throw Exception('init down');
        };

    await expectLater(
      NaverMapInit.ensureInitialized(clientId: null),
      throwsException,
    );
    await NaverMapInit.ensureInitialized(clientId: null);

    expect(calls, 2, reason: '실패한 Future 를 캐시하면 다시 시도하지 않아 1이다');
  });

  test('초기화가 성공하면 이후 호출은 SDK 를 다시 부르지 않는다', () async {
    NaverMapInit.initializer = ({
      required clientId,
      required onAuthFailed,
    }) async => calls++;

    await NaverMapInit.ensureInitialized(clientId: null);
    await NaverMapInit.ensureInitialized(clientId: null);

    expect(calls, 1);
  });

  testWidgets('reportInitFailure 가 켜져 있으면 초기화 예외가 onAuthFailed 에 닿는다', (
    tester,
  ) async {
    NaverMapInit.initializer = ({
      required clientId,
      required onAuthFailed,
    }) async => throw StateError('init down');

    await tester.pumpWidget(adapter(reportInitFailure: true));
    await tester.pump();

    expect(caught, hasLength(1));
    expect(caught.single, isA<StateError>());
  });

  testWidgets('reportInitFailure 가 꺼져 있으면 초기화 예외를 onAuthFailed 로 보내지 않는다', (
    tester,
  ) async {
    NaverMapInit.initializer = ({
      required clientId,
      required onAuthFailed,
    }) async => throw StateError('init down');

    await tester.pumpWidget(adapter(reportInitFailure: false));
    await tester.pump();

    expect(caught, isEmpty);
  });

  testWidgets('초기화에 실패한 뒤 새로 만든 지도는 다시 초기화를 시도한다', (tester) async {
    NaverMapInit.initializer =
        ({required clientId, required onAuthFailed}) async {
          calls++;
          throw StateError('init down');
        };

    await tester.pumpWidget(adapter(reportInitFailure: false));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(adapter(reportInitFailure: false));
    await tester.pump();

    expect(calls, 2);
  });
}
