import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'offline_queue_database.g.dart';

/// 오프라인 상태에서 쌓인 승하차 처리 요청 큐 (M-06, API_SPEC §1.7 멱등성).
///
/// 각 행은 재접속 시 그대로 재전송할 요청 하나 — 본문에 실을 `client_key`
/// 를 요청 생성 시점에 미리 발급해 둬서, 큐 재생과 즉시 전송이 서버 입장에서
/// 같은 멱등 키를 쓰게 한다.
class PendingRequests extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 호출할 엔드포인트 경로.
  TextColumn get endpoint => text()();

  /// HTTP 메서드 — §1.7 대상 두 종류가 `PATCH`(승하차 처리)·`POST`(비상
  /// 발신)로 서로 달라 재생 시 필요하다. 새 행은 호출부가 항상 명시한다.
  TextColumn get method => text().withDefault(const Constant('PATCH'))();

  /// 요청 본문 (JSON 직렬화된 문자열).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 서버가 5xx 로 응답해 재생에 실패한 횟수 — 통신 두절은 세지
  /// 않는다(행이 아니라 망의 문제). 상한(`OfflineQueueRepositoryImpl.maxAttempts`)에
  /// 닿은 행이 **영구 실패 행**이다 — 재생에서 빠지고 큐 화면에는 남는다.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// 마지막으로 받은 명단(M-M3 · UF-E-07) — 앱을 다시 켠 뒤 오프라인이어도 명단을 본다.
/// 회차마다 한 행이고 서버 응답 본문(§4.2)을 그대로 담는다. 계정 소유의 정보라 로그아웃·세션 만료에 비운다.
class CachedRosters extends Table {
  TextColumn get runId => text()();

  /// `GET /runs/{runId}/roster` 응답 본문(JSON 직렬화된 문자열).
  TextColumn get payload => text()();

  /// 서버에서 받은 시각 — 화면이 "N시 N분에 받은 명단" 으로 밝힌다.
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {runId};
}

@DriftDatabase(tables: [PendingRequests, CachedRosters])
class OfflineQueueDatabase extends _$OfflineQueueDatabase {
  new() : super(_openConnection());

  /// 시험 전용 — 파일 대신 주입받은 실행기(보통 `NativeDatabase.memory()`)를
  /// 쓴다. `path_provider` 플랫폼 채널이 없는 단위 시험 환경에서 필요하다.
  @visibleForTesting
  new forTesting(super.e);

  // 출시 전 개발 데이터는 버려도 되므로 스키마는 1판 하나다 — 표를 바꾸면 이 번호를 올리지 않고 앱을 지우고 다시 깐다.
  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'offline_queue.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
