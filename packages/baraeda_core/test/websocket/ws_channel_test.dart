import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsChannel', () {
    test('학생 채널 — API_SPEC §7 표의 실제 구독 경로와 일치', () {
      expect(WsChannel.studentRun('7'), '/topic/students/7/run');
    });

    test('매니저 채널', () {
      expect(WsChannel.managerRun('42'), '/topic/manager/runs/42');
    });

    test('학원 관제 채널', () {
      expect(WsChannel.academyLive('3'), '/topic/academy/3/live');
    });

    test('메인 관리자 채널 — 경로 파라미터 없음', () {
      expect(WsChannel.adminLive(), '/topic/admin/live');
    });
  });
}
