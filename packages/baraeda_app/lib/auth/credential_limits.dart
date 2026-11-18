import 'dart:convert';

/// API_SPEC §2.2·§2.8 — 비밀번호는 UTF-8 72바이트 이하(한글 24자). 넘으면 서버가 `422` 로 거절한다.
const int passwordMaxBytes = 72;

/// 새 비밀번호의 최소 길이(Ruling 938 C) — 글자 수만 본다(조합 규칙 없음). 로그인 입력에는 걸지 않는다.
const int passwordMinLength = 8;

/// 최소 길이에 못 미칠 때 입력란에 보일 이유.
const String passwordTooShortMessage = '비밀번호는 $passwordMinLength자 이상이어야 합니다';

/// API_SPEC §2.2 — `login_id` 는 50자 이하.
const int loginIdMaxLength = 50;

/// 입력칸 아래 상시 안내 — 한도를 넘으면 [passwordLengthError] 가 이 자리를 대신한다.
const String passwordLimitHint =
    '영문 $passwordMaxBytes자 · 한글 ${passwordMaxBytes ~/ 3}자까지';

/// 비워 두지 않았는데 최소 길이에 못 미치는가 — 빈 칸은 "아직 채우지 않음" 이 따로 알린다.
bool isPasswordTooShort(String password) =>
    password.isNotEmpty && password.length < passwordMinLength;

/// 새 비밀번호가 최소 길이에 못 미치거나 한도를 넘으면 입력란에 보일 이유, 아니면 `null`.
String? passwordLengthError(String password) {
  if (isPasswordTooShort(password)) return passwordTooShortMessage;
  return utf8.encode(password).length > passwordMaxBytes
      ? '비밀번호는 72바이트(한글 24자) 이하여야 해요'
      : null;
}

/// 아이디가 한도를 넘으면 입력란에 보일 이유, 아니면 `null`.
String? loginIdLengthError(String loginId) =>
    loginId.trim().length > loginIdMaxLength ? '아이디는 50자 이하여야 해요' : null;
