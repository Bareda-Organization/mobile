// 배포 시험 빌드 빠른 로그인 — 로그인 화면에서 역할별 시험 계정으로 한 번에 로그인한다.
//
// **왜 있나.** 팀원이 시험 서버에서 역할(학부모·학생·기사·동승자)마다 화면을
// 보려면 매번 아이디와 비밀번호를 손으로 쳐야 한다. 시험 빌드에만 역할별 단추를
// 둔다(Ruling 877 — 844·861⑤ 의 "사양 밖 요소 제거"를 시험 빌드 한정으로 뒤집음).
//
// ⚠ **켜는 조건은 빌드 때 준 값 하나다.** `--dart-define=QUICK_LOGIN_PASSWORD=…`
// 가 비어 있지 않을 때만 그린다. 디버그 빌드 한정(`kDebugMode`)이 아닌 이유 —
// 팀원에게 주는 APK 는 release 빌드다. 운영 빌드는 이 값을 주지 않으므로 단추도
// 비밀번호도 들어가지 않는다. 비밀번호는 소스에 적지 않는다.
import 'package:flutter/material.dart';

/// 빠른 로그인 단추 하나가 가리키는 시험 계정.
class QuickLoginAccount {
  const new(this.label, this.loginId);

  /// 단추에 적히는 이름 — 역할이 한눈에 보이게 적는다.
  final String label;
  final String loginId;
}

/// 로그인 화면 아래에 붙이는 역할별 시험 계정 단추 모음 — 배포 시험 빌드에서만 — Ruling 877.
///
/// [onPick] 은 아이디·비밀번호를 받아 **기존 로그인 경로를 그대로** 부른다 — 인증을 건너뛰지 않는다.
class QuickLogin extends StatelessWidget {
  const new({
    required this.accounts,
    required this.onPick,
    this.password = environmentPassword,
    super.key,
  });

  /// 빌드 때 `--dart-define=QUICK_LOGIN_PASSWORD` 로 준 값.
  /// 안 주면 빈 문자열이라 위젯이 아무것도 그리지 않는다.
  static const String environmentPassword = String.fromEnvironment(
    'QUICK_LOGIN_PASSWORD',
  );

  final List<QuickLoginAccount> accounts;
  final void Function(String loginId, String password) onPick;

  /// 단추가 넘길 비밀번호. 기본은 [environmentPassword] —
  /// `String.fromEnvironment` 는 컴파일 상수라 시험에서 못 바꾸므로 시험은 이
  /// 값을 직접 넘긴다.
  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '시험 빌드 빠른 로그인',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in accounts)
                OutlinedButton(
                  key: Key('quick-login-${a.loginId}'),
                  onPressed: () => onPick(a.loginId, password),
                  child: Text('${a.label} · ${a.loginId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
