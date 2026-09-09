import 'package:flutter/material.dart';

/// 자리표시 화면. 로그인 폼·역할 판정 흐름은 이번 범위가 아니다.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('LoginScreen — 자리표시')),
    );
  }
}
