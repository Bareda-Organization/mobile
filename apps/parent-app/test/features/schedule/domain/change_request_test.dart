import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/schedule/domain/change_request.dart';

/// §3.8·§3.9 파싱 시험 — `pending_count` 는 홈 배지가 그대로 읽는
/// 값이라 봉투 레벨 필드가 빠지면 홈 화면 배지가 조용히 틀린 값을
/// 보여주게 된다.
void main() {
  test('ChangeRequestPage.fromJson 은 items 와 pending_count 를 함께 읽는다', () {
    final page = ChangeRequestPage.fromJson({
      'items': [
        {
          'change_request_id': 'cr-1',
          'type': 'relocate',
          'status': 'pending',
          'run_id': 'run-1',
          'requested_at': '2026-09-12T00:00:00Z',
        },
      ],
      'pending_count': 1,
    });

    expect(page.items, hasLength(1));
    expect(page.items.first.type, ChangeRequestType.relocate);
    expect(page.items.first.status, ChangeRequestStatus.pending);
    expect(page.pendingCount, 1);
  });

  test('ChangeRequestPage.fromJson 은 items 부재 시 빈 리스트로 채운다', () {
    final page = ChangeRequestPage.fromJson({'pending_count': 0});

    expect(page.items, isEmpty);
  });

  test('ChangeRequestStatus.fromWireValue 는 auto_rejected 를 옮긴다', () {
    expect(
      ChangeRequestStatus.fromWireValue('auto_rejected'),
      ChangeRequestStatus.autoRejected,
    );
  });

  test('ChangeRequestType.wireValue 는 enum 이름을 그대로 돌려준다', () {
    expect(ChangeRequestType.cancel.wireValue, 'cancel');
  });
}
