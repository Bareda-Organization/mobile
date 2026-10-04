import 'dart:convert';

/// API_SPEC §2.2·§2.8 — 비밀번호는 UTF-8 72바이트 이하(한글 24자). 넘으면 서버가 `422` 로 거절한다.
const int passwordMaxBytes = 72;

/// API_SPEC §2.2 — `login_id` 는 50자 이하.
const int loginIdMaxLength = 50;

/// 비밀번호가 한도를 넘으면 입력란 옆에 보일 이유, 아니면 `null`(F05-11).
/// 입력칸 아래 상시 안내 — 한도를 넘으면 [passwordLengthError] 가 이 자리를 대신한다.
const String passwordLimitHint =
    '영문 $passwordMaxBytes자 · 한글 ${passwordMaxBytes ~/ 3}자까지';

String? passwordLengthError(String password) =>
    utf8.encode(password).length > passwordMaxBytes
    ? '비밀번호는 72바이트(한글 24자) 이하여야 합니다'
    : null;

/// 아이디가 한도를 넘으면 입력란 옆에 보일 이유, 아니면 `null`(F05-11).
String? loginIdLengthError(String loginId) =>
    loginId.trim().length > loginIdMaxLength ? '아이디는 50자 이하여야 합니다' : null;
