import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:baraeda_ui/widgets/transit/student_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [StudentRow] 의 아바타 대체 표시 — §4.2(2026-09-14 확정). `photoUrl` 이
/// `null`·로드 실패·로딩 중일 때 전부 이름 뒤 2자 이니셜로 떨어지는지,
/// 로드에 성공하면 사진으로 바뀌는지를 확인한다.
///
/// 실 네트워크를 타지 않도록 `debugNetworkImageHttpClientProvider` 로
/// [HttpClient] 를 가짜로 바꾼다 — Flutter SDK 자체 테스트
/// (`image_provider_network_image_test.dart`)가 쓰는 것과 같은 방식이다.
///
/// ⚠ `testWidgets` 는 테스트 본문이 반환된 *직후* 디버그 전역값이 원래대로인지
/// 검사한다 — `setUp`/`tearDown`(package:test) 은 그보다 늦게 실행되므로
/// 여기서는 쓸 수 없다. 대신 각 테스트 본문 안에서 `try`/`finally` 로 직접
/// 원복한다.
void main() {
  Future<void> pumpRow(
    WidgetTester tester,
    _FakeHttpClient httpClient, {
    String? photoUrl,
    Map<String, String>? photoHeaders,
  }) async {
    debugNetworkImageHttpClientProvider = () => httpClient;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentRow(
            name: '김서준',
            photoUrl: photoUrl,
            photoHeaders: photoHeaders,
          ),
        ),
      ),
    );
  }

  void restore() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  testWidgets('photoUrl이 null이면 이니셜을 그린다', (tester) async {
    final httpClient = _FakeHttpClient();
    try {
      await pumpRow(tester, httpClient);
      expect(find.text('서준'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    } finally {
      restore();
    }
  });

  testWidgets('photoUrl이 빈 문자열이어도 이니셜을 그린다', (tester) async {
    final httpClient = _FakeHttpClient();
    try {
      await pumpRow(tester, httpClient, photoUrl: '');
      expect(find.text('서준'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    } finally {
      restore();
    }
  });

  testWidgets('photoUrl 로드가 끝나기 전에는 이니셜 자리를 유지한다', (tester) async {
    final httpClient = _FakeHttpClient()..completeManually = true;
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/s/301.jpg',
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('서준'), findsOneWidget);
      httpClient.finish();
      await tester.pumpAndSettle();
    } finally {
      restore();
    }
  });

  testWidgets('photoUrl 로드에 성공하면 사진으로 바뀐다', (tester) async {
    final httpClient = _FakeHttpClient()
      ..response.contentLength = _transparentPng.length
      ..response.content = [_transparentPng];
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/s/301.jpg',
      );
      // 이미지 디코드는 `SchedulerBinding` 이 별도 태스크로 미루므로,
      // 가짜 시간만 흘리는 `pump`/`pumpAndSettle` 로는 끝나지 않는다.
      // `runAsync` 로 실제 이벤트 루프를 한 번 돌려 디코드가 끝나게 한다.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('서준'), findsNothing);
    } finally {
      restore();
    }
  });

  // Ruling 377 — 학생 사진은 로그인 토큰이 있어야 받는다. 위젯은 토큰을 모르고
  // 앱이 넘긴 헤더를 이미지 요청에 그대로 싣기만 한다.
  testWidgets('photoHeaders 를 이미지 요청 헤더로 싣는다', (tester) async {
    final httpClient = _FakeHttpClient()
      ..response.contentLength = _transparentPng.length
      ..response.content = [_transparentPng];
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/api/v1/files/photos/301.jpg',
        photoHeaders: const {'Authorization': 'Bearer tok-1'},
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(httpClient.request.headers.added['Authorization'], 'Bearer tok-1');
    } finally {
      restore();
    }
  });

  // F07-12 — 38px 아바타인데 원본 해상도로 디코딩하면 행 수만큼 메모리가 오른다.
  testWidgets('사진은 표시 크기(38px × 기기 픽셀 비율)로 줄여 디코딩한다', (tester) async {
    final httpClient = _FakeHttpClient()
      ..response.contentLength = _transparentPng.length
      ..response.content = [_transparentPng];
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/s/301.jpg',
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(image, isA<ResizeImage>());
      expect(
        (image as ResizeImage).width,
        (38 * tester.view.devicePixelRatio).round(),
      );
    } finally {
      restore();
    }
  });

  testWidgets('photoUrl 로드가 실패하면(404) 이니셜로 떨어진다', (tester) async {
    final httpClient = _FakeHttpClient()
      ..response.statusCode = HttpStatus.notFound;
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/s/broken.jpg',
      );
      await tester.pumpAndSettle();
      expect(find.text('서준'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      restore();
    }
  });

  testWidgets('photoUrl 요청 자체가 예외를 던져도 이니셜로 떨어진다', (tester) async {
    final httpClient = _FakeHttpClient()
      ..thrownError = const SocketException('no route to host');
    try {
      await pumpRow(
        tester,
        httpClient,
        photoUrl: 'https://cdn.example/s/broken.jpg',
      );
      await tester.pumpAndSettle();
      expect(find.text('서준'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      restore();
    }
  });
}

final Uint8List _transparentPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x06, 0x62, 0x4B, 0x47, 0x44, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xA0,
  0xBD, 0xA7, 0x93, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 0x00,
  0x00, 0x0B, 0x13, 0x00, 0x00, 0x0B, 0x13, 0x01, 0x00, 0x9A, 0x9C, 0x18,
  0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4D, 0x45, 0x07, 0xE6, 0x03, 0x10,
  0x17, 0x07, 0x1D, 0x2E, 0x5E, 0x30, 0x9B, 0x00, 0x00, 0x00, 0x0B, 0x49,
  0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0x60, 0x00, 0x02, 0x00, 0x00, 0x05,
  0x00, 0x01, 0xE2, 0x26, 0x05, 0x9B, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeHttpClient extends Fake implements HttpClient {
  final _FakeHttpClientRequest request = _FakeHttpClientRequest();
  _FakeHttpClientResponse get response => request.response;
  Exception? thrownError;
  bool completeManually = false;
  final _hold = Completer<void>();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (thrownError != null) {
      throw thrownError!;
    }
    request.hold = completeManually ? _hold.future : null;
    return request;
  }

  void finish() {
    if (!_hold.isCompleted) _hold.complete();
  }
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  final _FakeHttpClientResponse response = _FakeHttpClientResponse();
  Future<void>? hold;

  @override
  final _FakeHttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    if (hold != null) await hold;
    return response;
  }
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int statusCode = HttpStatus.ok;
  @override
  int contentLength = -1;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  List<List<int>> content = const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(content).listen(
      onData,
      onDone: onDone,
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<E> drain<E>([E? futureValue]) async {
    return futureValue ?? futureValue as E;
  }
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, Object> added = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    added[name] = value;
  }
}
