import 'package:flutter/widgets.dart';

/// 자유 입력 메모 칸 아래에 붙이는 안내(R46-LAST `Ruling 583`) — 이 칸들은 퇴원한 학생의 개인정보 파기
/// 대상 밖이라 학생 이름·연락처가 한 번 적히면 남는다. 지울 수 없으니 입력 단계에서 줄인다.
const freeTextPrivacyNotice = '학생 이름·연락처는 적지 마세요';

/// 입력이 [maxLength] 를 넘으면 그 길이에서 잘라 내는 컨트롤러. 서버가 자유 입력 메모를 200자로
/// 제한하고 넘으면 `422` 를 내므로(API_SPEC §1) 입력칸에서 먼저 멈춘다. 공용 `BaraedaTextarea` 는
/// 길이 제한 인자가 없어 컨트롤러 쪽에서 막는다.
class LimitedTextController extends TextEditingController {
  new({this.maxLength = memoMaxLength});

  /// 자유 입력 메모·비고의 최대 길이(API_SPEC §1, 2026-09-30 BR-255 · BR-257).
  static const memoMaxLength = 200;

  final int maxLength;

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text.length <= maxLength) {
      super.value = newValue;
      return;
    }
    var end = maxLength;
    // 글자(surrogate pair) 한가운데서 자르지 않는다.
    if (_isHighSurrogate(newValue.text.codeUnitAt(end - 1))) end--;
    super.value = newValue.copyWith(
      text: newValue.text.substring(0, end),
      selection: TextSelection.collapsed(offset: end),
      composing: TextRange.empty,
    );
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}
