// Android `main` 매니페스트의 권한 선언.
//
// 인터넷 권한은 debug · profile 매니페스트에만 Flutter 가 넣어 주고, 릴리스 빌드는 지도 SDK 가 병합해 넣어 주는 데
// 기댔다(L8). 지도 SDK 를 바꾸면 릴리스 앱만 네트워크가 끊기므로 `main` 에 직접 선언한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('L8 Android main 매니페스트가 INTERNET 권한을 직접 선언한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"'),
    );
  });
}
