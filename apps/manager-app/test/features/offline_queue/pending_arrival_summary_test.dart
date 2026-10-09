import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';

/// 859 — 도착 처리 요청이 큐 화면에서 사람이 읽는 이름을 갖고, 운행 화면이 승하차지를 가릴 수 있다.
void main() {
  PendingRequestSummary request(String endpoint) => PendingRequestSummary(
    id: 1,
    endpoint: endpoint,
    method: 'POST',
    payload: '{}',
    createdAt: DateTime(2026, 10, 10, 8),
  );

  test('도착 처리 요청은 승하차지 id 와 이름을 낸다', () {
    final arrive = request('/runs/3/stops/s7/arrive');

    expect(arrive.isArrive, isTrue);
    expect(arrive.arriveStopId, 's7');
    expect(arrive.description, '승하차지 도착 처리');
    expect(arrive.riderId, isNull);
  });

  test('도착 처리가 아닌 요청은 승하차지 id 가 없다', () {
    final rider = request('/runs/3/riders/9');

    expect(rider.isArrive, isFalse);
    expect(rider.arriveStopId, isNull);
  });
}
