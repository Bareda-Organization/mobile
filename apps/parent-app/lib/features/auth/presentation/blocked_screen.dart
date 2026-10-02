import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// UF-X-04 — 계정 차단 안내.
///
/// 로그인 자체가 `403 AUTH_ACCOUNT_BLOCKED` 로 실패한 결과라 토큰·role·
/// status 어느 것도 만들어지지 않는다 — `router.dart` 의 declarative
/// `redirect` 로는 표현할 수 없어 `LoginScreen` 이 이 화면을 직접
/// `context.push` 한다(`app/router.dart` 의 redirect 는 이 경로를 벗어나게
/// 하지 않도록 예외 처리돼 있다).
///
/// 차단 범위는 계정 단위뿐이다(IP 차단 아님) — 다른 기기·다른 계정 로그인은
/// 이 화면과 무관하다. 자가 해제 수단은 없고 학원 메인 관리자만 해제할 수 있지만, 사용자에게는
/// 그 구분을 알릴 이유가 없어 문의처를 "학원" 하나로만 적는다(R32 P13). 이 화면은 안내와
/// 로그인 화면 복귀만 제공한다.
class BlockedScreen extends StatelessWidget {
  /// `/blocked-account`. `LoginScreen` 이 `context.push` 로만 진입시킨다.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
            child: EmptyState(
              icon: 'circle-alert',
              title: '계정이 차단되었습니다',
              body:
                  '로그인 5회 실패로 계정이 잠겼습니다. 직접 풀 수는 없으니 '
                  '학원에 문의해 주세요.',
              action: BaraedaButton(
                label: '로그인 화면으로 돌아가기',
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
