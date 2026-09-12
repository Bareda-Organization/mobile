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

  /// API_SPEC §1.7 멱등 키 — 단말에서 미리 발급한 UUID. 즉시 전송이
  /// 실패해 큐에 들어갈 때도, 큐를 재생할 때도 이 값 그대로 다시 보낸다
  /// — 재시도마다 새로 발급하면 서버가 같은 요청을 다른 시도로 봐
  /// 멱등성이 깨진다(M-06 브리프의 명시적 경고).
  ///
  /// ⚠ 실제 멱등성은 이 컬럼이 아니라 `payload` 안에 직렬화된
  /// `client_key` 값으로 동작한다(`replayPending()` 이 `jsonDecode(row.
  /// payload)` 를 그대로 재전송한다, `offline_queue_repository_impl.dart`).
  /// 이 컬럼은 **쓰기만 되고 어디서도 읽히지 않는다** — 로컬 DB 를 직접
  /// 열어 요청을 식별할 때 쓰는 조회용 인덱스로 남겨 뒀다(제거하려면
  /// 스키마 버전을 올려야 해 이번 라운드에서는 손대지 않았다). 새로
  /// 이 값을 근거로 중복 판정 로직을 짜지 마라 — payload 쪽이 정본이다.
  TextColumn get clientKey => text()();

  /// 호출할 엔드포인트 경로.
  TextColumn get endpoint => text()();

  /// HTTP 메서드 — §1.7 대상 두 종류가 `PATCH`(승하차 처리)·`POST`(비상
  /// 발신)로 서로 달라 재생 시 필요하다(스키마 v2 에서 추가, 기존
  /// 컬럼과 달리 처음부터 있었어야 했던 값). 기본값은 `ALTER TABLE ADD
  /// COLUMN` 이 기존 행에 값을 채우는 데 쓰인다 — 새 행은 호출부가 항상
  /// 명시한다.
  TextColumn get method => text().withDefault(const Constant('PATCH'))();

  /// 요청 본문 (JSON 직렬화된 문자열).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [PendingRequests])
class OfflineQueueDatabase extends _$OfflineQueueDatabase {
  OfflineQueueDatabase() : super(_openConnection());

  /// 시험 전용 — 파일 대신 주입받은 실행기(보통 `NativeDatabase.memory()`)를
  /// 쓴다. `path_provider` 플랫폼 채널이 없는 단위 시험 환경에서 필요하다.
  @visibleForTesting
  OfflineQueueDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 에는 `method` 가 없었다 — 컬럼 기본값(`PATCH`, 그 시점 유일한
        // 대상인 §4.6 승하차 처리)이 기존 행을 그대로 채운다.
        await m.addColumn(pendingRequests, pendingRequests.method);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'offline_queue.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
