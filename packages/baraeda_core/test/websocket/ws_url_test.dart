import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wsUrlFromApiBaseUrl', () {
    test('http → ws, 경로는 /ws/location 으로 고정', () {
      expect(
        wsUrlFromApiBaseUrl('http://localhost:8161/api/v1'),
        'ws://localhost:8161/ws/location',
      );
    });

    test('https → wss (배포 환경)', () {
      expect(
        wsUrlFromApiBaseUrl('https://api.example.com/api/v1'),
        'wss://api.example.com/ws/location',
      );
    });

    test('쿼리·프래그먼트가 있어도 경로만 교체된다', () {
      expect(
        wsUrlFromApiBaseUrl('http://localhost:8080/api/v1?x=1'),
        'ws://localhost:8080/ws/location',
      );
    });
  });
}
