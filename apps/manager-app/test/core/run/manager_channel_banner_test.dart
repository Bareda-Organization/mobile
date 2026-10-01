import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// [managerChannelBannerContentFor] 만 검증한다. [ManagerChannelBanner]
/// 자체(`ConsumerWidget`)는 `managerRunChannelProvider` 를 통해 실제
/// WebSocket 연결을 여는 [ManagerRunChannelController] 에 묶여 있어, 화면
/// 수준 위젯 시험으로는 가짜 컨트롤러를 깨끗하게 주입할 수 없다 — 그래서
/// 문구·톤 결정 로직만 떼어 여기서 순수 함수로 검증한다(파일 문서 참고,
/// 보고서 §1·§2).
void main() {
  group('managerChannelBannerContentFor', () {
    test('connected 는 배너를 그리지 않는다(null)', () {
      expect(
        managerChannelBannerContentFor(ManagerChannelStatus.connected),
        isNull,
      );
    });

    test('connecting 은 moving 톤 — 정상 범위 안의 대기라 심각하지 않다', () {
      final content = managerChannelBannerContentFor(
        ManagerChannelStatus.connecting,
      );
      expect(content, isNotNull);
      expect(content!.tone, AlertTone.moving);
    });

    test('reconnecting 은 moving 톤 — 자동 복구 중이라 아직 심각하지 않다', () {
      final content = managerChannelBannerContentFor(
        ManagerChannelStatus.reconnecting,
      );
      expect(content, isNotNull);
      expect(content!.tone, AlertTone.moving);
    });

    test('gaveUp 은 missed 톤 — 자동 복구가 멈춘 상태라 사람이 개입해야 한다', () {
      final content = managerChannelBannerContentFor(
        ManagerChannelStatus.gaveUp,
      );
      expect(content, isNotNull);
      expect(content!.tone, AlertTone.missed);
    });

    test('forbidden 은 missed 톤 — 재시도 자체가 무의미한 상태다', () {
      final content = managerChannelBannerContentFor(
        ManagerChannelStatus.forbidden,
      );
      expect(content, isNotNull);
      expect(content!.tone, AlertTone.missed);
    });

    // R46-FIXCONN C-12 — 같은 끊김을 웹·학부모 앱과 같은 제목으로 알린다.
    // 권한 거부(forbidden)는 이 앱에서 "배정되지 않음" 이라는 업무 의미가 있어 그 문구를 유지한다.
    test('끊김 제목이 웹·학부모 앱과 같은 공용 문구다', () {
      expect(
        managerChannelBannerContentFor(
          ManagerChannelStatus.reconnecting,
        )!.title,
        WsConnectionNotice.reconnectingTitle,
      );
      expect(
        managerChannelBannerContentFor(ManagerChannelStatus.gaveUp)!.title,
        WsConnectionNotice.gaveUpTitle,
      );
    });

    test('gaveUp 과 forbidden 은 톤이 같아도 문구로 원인이 구별된다', () {
      final gaveUp = managerChannelBannerContentFor(
        ManagerChannelStatus.gaveUp,
      )!;
      final forbidden = managerChannelBannerContentFor(
        ManagerChannelStatus.forbidden,
      )!;
      expect(gaveUp.title, isNot(forbidden.title));
      expect(gaveUp.body, isNot(forbidden.body));
    });
  });
}
