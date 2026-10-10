// Android `main` 매니페스트의 권한 선언(R52 M4 · A15).
//
// - 위치: Android 12+ 는 정밀 위치(`ACCESS_FINE_LOCATION`) 단독 요청에
//   권한 창을 띄우지 않을 수 있어 대략 위치(`ACCESS_COARSE_LOCATION`)를 함께
//   선언해야 한다. 실기기에서의 권한 창 확인은 이 시험이 대신하지 못한다.
// - 인터넷: debug · profile 매니페스트에만 Flutter 가 넣어 주고 릴리스는 지도
//   SDK 병합에 기댄다. 지도 SDK 를 바꾸면 릴리스 앱만 네트워크가 끊기므로
//   `main` 에 직접 선언한다(학부모 앱 L8 과 같다).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  for (final permission in [
    'ACCESS_COARSE_LOCATION',
    'ACCESS_FINE_LOCATION',
    'INTERNET',
  ]) {
    test('Android main 매니페스트가 $permission 권한을 직접 선언한다', () {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.$permission"',
        ),
      );
    });
  }
}
