import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 명단 행 사진 한 장을 요청하는 데 필요한 값 — 주소와(있다면) 인증 헤더.
typedef RosterPhoto = ({String url, Map<String, String>? headers});

/// §4.2 `photo_url` 을 이미지 요청 값으로 바꾼다(Ruling 377).
///
/// - `null`·빈 값 → `null` (미등록이 기본 상태라 이니셜로 그린다)
/// - 상대 경로(`/api/v1/files/photos/..`) → [baseUrl] 의 호스트에 붙이고 토큰 헤더를 싣는다.
///   경로에 `/api/v1` 이 이미 들어 있어 `baseUrl` 전체를 앞에 붙이면 두 번 붙으므로
///   `Uri.resolve` 로 호스트만 취한다. 토큰을 아직 못 읽었으면([authHeaders] `null`)
///   401 만 맞을 요청을 보내지 않고 `null` 로 둔다.
/// - 절대 URL(옛 공개 주소) → 그대로. 남의 호스트에 토큰이 새지 않게 헤더는 싣지 않는다.
RosterPhoto? resolveRosterPhoto(
  String? raw, {
  required String baseUrl,
  required Map<String, String>? authHeaders,
}) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/')) return (url: raw, headers: null);
  if (authHeaders == null) return null;
  final url = Uri.parse(baseUrl).resolve(raw).toString();
  return (url: url, headers: authHeaders);
}

/// 학생 사진 전용 디스크 캐시 — 명단 행마다 사진을 다시 받지 않는다. 사진은 개인정보라
/// 하루 뒤 만료되고 로그아웃 · 세션 만료에 비운다([studentPhotoCacheClearerProvider]).
/// 요청은 [RosterPhoto] 의 인증 헤더를 그대로 싣는다.
final CacheManager studentPhotoCacheManager = CacheManager(
  Config(
    'student_photos',
    stalePeriod: const Duration(days: 1),
    maxNrOfCacheObjects: 300,
  ),
);

/// 받아 둔 학생 사진을 디스크에서 지우는 동작 — 계정별 정리가 부른다. 시험이 가짜로 덮는다.
final Provider<Future<void> Function()> studentPhotoCacheClearerProvider =
    Provider<Future<void> Function()>(
      (ref) =>
          () => wipeStudentPhotosGuarded(
            // 저장소는 구역 안에서 처음 만들어져야 임시 폴더 읽기 오류도 구역이
            // 받는다 — 함수 참조로 바꾸면 구역 밖에서 만들어진다.
            // ignore: unnecessary_lambdas
            () => studentPhotoCacheManager.emptyCache(),
          ),
    );

/// [wipe] 를 구역 안에서 돌려 오류가 호출한 쪽 밖으로 새지 않게 하고, 오류는 로그로 남긴다.
///
/// 캐시 저장소를 처음 만들 때 임시 폴더를 읽는 비동기 작업이 같이 시작된다 — 플랫폼 플러그인이 없는
/// 환경(단위 시험)이나 폴더를 못 읽는 기기에서는 그 작업이 호출한 쪽 밖으로 오류를 흘린다. 못 지워도
/// 사진은 하루 뒤 스스로 만료되므로 정리는 이어가되, 조용히 삼키지 않는다.
@visibleForTesting
Future<void> wipeStudentPhotosGuarded(Future<void> Function() wipe) {
  final done = Completer<void>();
  unawaited(
    runZonedGuarded(
      () async {
        try {
          await wipe();
        } finally {
          done.complete();
        }
      },
      (error, stack) => debugPrint('학생 사진 캐시를 지우지 못했어요: $error'),
    ),
  );
  return done.future;
}
