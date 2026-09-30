import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/ui/failure_message.dart';

/// K-01 — REST 재발급 401 은 `Failure.unauthenticated` 로 오는데
/// 기본 분기 문구(알 수 없는 실패)가 나갔다.
void main() {
  test('재로그인이 필요한 실패(unauthenticated)는 기본 문구가 아니라 다시 로그인하라고 안내한다', () {
    final message = failureMessage(
      const Failure.unauthenticated(),
      fallback: '알 수 없는 오류',
    );

    expect(message, isNot('알 수 없는 오류'));
    expect(message, contains('다시 로그인'));
  });
}
