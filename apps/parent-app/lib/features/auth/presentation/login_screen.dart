import 'package:flutter/material.dart';

/// 자리표시 화면 — AUTH-01~11 · P-01 (IMPLEMENTATION_PLAN.md §3.1).
/// 실제 로그인 폼·`POST /auth/login` 호출은 이번 범위가 아니다.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('LoginScreen — 자리표시')),
    );
  }
}
