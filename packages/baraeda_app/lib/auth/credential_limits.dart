import 'dart:convert';

/// API_SPEC §2.2·§2.8 — 비밀번호는 UTF-8 72바이트 이하(한글 24자). 넘으면 서버가 `422` 로 거절한다.
const int passwordMaxBytes = 72;

/// 새 비밀번호의 최소 길이(Ruling 938 C) — 글자 수만 본다(조합 규칙 없음). 로그인 입력에는 걸지 않는다.
const int passwordMinLength = 8;


/// API_SPEC §2.2 — `login_id` 는 50자 이하.
const int loginIdMaxLength = 50;

/// 입력칸 아래 상시 안내 — 한도를 넘으면 [passwordLengthError] 가 이 자리를 대신한다.
const String passwordLimitHint =
    '영문 $passwordMaxBytes자 · 한글 ${passwordMaxBytes ~/ 3}자까지';

/// 새 비밀번호가 최소 길이에 못 미치면 입력란에 보일 이유, 아니면 `null`.
/// 빈 칸은 "아직 채우지 않음" 이 따로 알리므로 `null` 이다. 네 화면(가입 · 비밀번호 변경 × 두 앱)이 이 함수 하나를 쓴다.
String? passwordTooShortError(String password) =>
    password.isNotEmpty && password.length < passwordMinLength
    ? '비밀번호는 $passwordMinLength자 이상이어야 합니다'
    : null;

/// 새 비밀번호가 최소 길이에 못 미치거나 한도를 넘으면 입력란에 보일 이유, 아니면 `null`.
String? passwordLengthError(String password) {
  final tooShort = passwordTooShortError(password);
  if (tooShort != null) return tooShort;
  return utf8.encode(password).length > passwordMaxBytes
      ? '비밀번호는 72바이트(한글 24자) 이하여야 해요'
      : null;
}

/// 아이디가 한도를 넘으면 입력란에 보일 이유, 아니면 `null`.
String? loginIdLengthError(String loginId) =>
    loginId.trim().length > loginIdMaxLength ? '아이디는 50자 이하여야 해요' : null;
