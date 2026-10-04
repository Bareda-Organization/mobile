/// §4.9 지연 알림 `reason` 4종 → 화면 글자 — 매니저 앱(사유 고르기·영수증)과 학부모 앱(지연 띠)이 같이 읽는다.
const _delayReasonLabels = {
  'traffic': '교통 체증',
  'weather': '기상 악화',
  'vehicle_check': '차량 점검',
  'prev_stop_wait': '앞 승하차지 대기',
};

/// [reason] 의 한글. **모르는 값 · 값이 없음은 `null`** — 서버 코드를 그대로 화면 글자로 쓰지 않도록,
/// 부르는 쪽이 사유 줄을 숨긴다.
String? delayReasonLabel(String? reason) => _delayReasonLabels[reason];
