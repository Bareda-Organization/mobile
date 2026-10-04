// 개발용 빠른 로그인 — 로그인 화면에서 시드 계정을 한 번에 채워 넣는다.
//
// **왜 있나.** 화면을 눈으로 확인하려면 매번 로그인해야 하는데, 시뮬레이터에 아이디·비밀번호를
// 손으로(또는 자동화로) 넣는 일이 번번이 실패한다 — 글자가 섞이거나, 칸을 눌렀는데 초점이 안 가거나,
// 입력 중에 화면이 스크롤돼 좌표가 바뀐다. 2026-09-21 사용자 지시로 이 우회로를 만들었다.
//
// ⚠ **디버그 빌드에만 나온다.** [DevQuickLogin] 이 `kDebugMode` 가 아니면(릴리스·프로파일) 빈 위젯을
// 돌려주므로 트리 자체가 안 생긴다. 비밀번호 상수도 **로컬 시드 전용**이다 — demo·prod 는
// SSM 에서 받은 다른 값을 쓴다(`CLAUDE.md` Flyway 항목).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 빠른 로그인 버튼 하나가 가리키는 시드 계정.
class DevAccount {
  const new(this.label, this.loginId);

  /// 버튼에 적히는 이름 — 역할이 한눈에 보이게 적는다.
  final String label;
  final String loginId;
}

/// 로그인 화면 아래에 붙이는 개발용 계정 단추 모음.
///
/// [onPick] 은 아이디·비밀번호를 받아 **곧바로 로그인까지** 수행한다 — 채워 넣기만 하면
/// 결국 제출 버튼을 또 눌러야 해서 문제가 반쯤만 풀린다.
class DevQuickLogin extends StatelessWidget {
  const new({required this.accounts, required this.onPick, super.key});

  /// 로컬 Flyway 시드(`V2__seed_data.sql`)가 심는 비밀번호. 전 계정 공통이다.
  static const String seedPassword = 'password';

  final List<DevAccount> accounts;
  final void Function(String loginId, String password) onPick;

  @override
  Widget build(BuildContext context) {
    // 디버그가 아닌 빌드(릴리스·프로파일)에서는 트리에 아예 넣지 않는다 — 프로파일 빌드는
    // kReleaseMode 가 false 라 예전 조건으로는 시드 계정 목록이 그대로 나갔다.
    if (!kDebugMode) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '개발용 빠른 로그인 (디버그 빌드에서만 표시)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in accounts)
                OutlinedButton(
                  key: Key('dev-login-${a.loginId}'),
                  onPressed: () => onPick(a.loginId, seedPassword),
                  child: Text(
                    '${a.label}\n${a.loginId}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
