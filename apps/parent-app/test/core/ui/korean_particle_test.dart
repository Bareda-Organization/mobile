import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/ui/korean_particle.dart';

void main() {
  test('받침이 있으면 으로, 없거나 ㄹ 이면 로, 한글이 아니면 (으)로', () {
    expect(euroOf('하늘수학 상동분원'), '으로'); // 원 — ㄴ 받침
    expect(euroOf('바래다'), '로'); // 다 — 받침 없음
    expect(euroOf('바래다학교'), '로'); // 교 — 받침 없음
    expect(euroOf('수학교실'), '로'); // 실 — ㄹ 받침은 로
    expect(euroOf('A학원2'), '(으)로');
  });
}
