import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// §4.9 지연 알림 `reason` 4종 → 화면 글자. 두 앱(매니저 · 학부모)이 이 표 하나를 같이 읽는다.
void main() {
  test('사유 4종은 각각 한글이다', () {
    expect(delayReasonLabel('traffic'), '교통 체증');
    expect(delayReasonLabel('weather'), '기상 악화');
    expect(delayReasonLabel('vehicle_check'), '차량 점검');
    expect(delayReasonLabel('prev_stop_wait'), '앞 승하차지 대기');
  });

  test('모르는 값 · 값이 없음은 null 이다 — 서버 코드를 글자로 돌려주지 않는다', () {
    expect(delayReasonLabel('flat_tire'), isNull);
    expect(delayReasonLabel('교통 체증'), isNull);
    expect(delayReasonLabel(''), isNull);
    expect(delayReasonLabel(null), isNull);
  });
}
