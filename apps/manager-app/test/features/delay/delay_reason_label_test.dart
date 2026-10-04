import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';

/// 사유 고르기 화면이 두 앱 공용 표(`delayReasonLabel`)에서 글자를 읽는다 — 사유를 더하고 표에 안 넣으면
/// 화면이 열릴 때 터지므로, 표가 모든 사유를 갖고 있는지 여기서 먼저 잡는다.
void main() {
  test('DelayReason 의 모든 값이 공용 표에 한글을 갖고 있다', () {
    for (final reason in DelayReason.values) {
      expect(
        delayReasonLabel(reason.wireValue),
        isNotNull,
        reason: '${reason.wireValue} 의 한글이 baraeda_core 표에 없다',
      );
    }
  });
}
