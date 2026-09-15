import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/account.dart';
import 'package:gemdori/app/score_reporter.dart';

// 점수 올리기 — 서버 기록보다 높을 때만 · 실패해도 멈추지 않음 · 앱 열 때 기기 기록 맞추기 (Firebase 없이)

class _FakeStore implements RankingStore {
  final Map<String, int> saved = {};
  int reads = 0;
  int writes = 0;
  bool failRead = false;

  String _key(String gameId, String uid) => '$gameId/$uid';

  @override
  Future<int?> bestOf(String gameId, String uid) async {
    reads++;
    if (failRead) throw Exception('offline');
    return saved[_key(gameId, uid)];
  }

  @override
  Future<void> save(String gameId, String uid, int score) async {
    writes++;
    saved[_key(gameId, uid)] = score;
  }
}

class _FakeAccount implements AccountSource {
  _FakeAccount(this.id, {this.fail = false});

  final String? id;
  final bool fail;
  int asked = 0;

  @override
  Future<Account> current() async {
    asked++;
    if (fail) throw Exception('no network');
    return Account(kind: AccountKind.guest, id: id);
  }
}

void main() {
  const uid = 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf';

  test('서버 기록이 없으면 올린다', () async {
    final store = _FakeStore();
    final r = ScoreReporter(account: _FakeAccount(uid), store: store);
    expect(await r.report('brick', 30), isTrue);
    expect(store.saved['brick/$uid'], 30);
  });

  test('서버 기록보다 높을 때만 올린다 — 같거나 낮으면 쓰지 않는다', () async {
    final store = _FakeStore()..saved['brick/$uid'] = 30;
    final r = ScoreReporter(account: _FakeAccount(uid), store: store);
    expect(await r.report('brick', 20), isFalse);
    expect(await r.report('brick', 30), isFalse, reason: '같은 점수는 새 기록이 아니다');
    expect(store.writes, 0);
    expect(await r.report('brick', 31), isTrue);
    expect(store.saved['brick/$uid'], 31);
  });

  test('0점은 올리지 않는다 — 계정도 묻지 않는다', () async {
    final account = _FakeAccount(uid);
    final store = _FakeStore();
    final r = ScoreReporter(account: account, store: store);
    expect(await r.report('brick', 0), isFalse);
    expect(account.asked, 0);
    expect(store.reads, 0);
  });

  test('아이디가 없으면(발급 전·실패) 올리지 않는다', () async {
    final store = _FakeStore();
    final r = ScoreReporter(account: _FakeAccount(null), store: store);
    expect(await r.report('brick', 30), isFalse);
    expect(store.reads, 0);
  });

  test('계정 확인이나 서버 읽기가 실패해도 오류 없이 false', () async {
    final r1 = ScoreReporter(account: _FakeAccount(uid, fail: true), store: _FakeStore());
    expect(await r1.report('brick', 30), isFalse);

    final store = _FakeStore()..failRead = true;
    final r2 = ScoreReporter(account: _FakeAccount(uid), store: store);
    expect(await r2.report('brick', 30), isFalse);
    expect(store.writes, 0);
  });

  test('앱을 열 때 기기 기록이 서버보다 높은 게임만 올린다', () async {
    final store = _FakeStore()..saved['old/$uid'] = 90;
    final r = ScoreReporter(account: _FakeAccount(uid), store: store);
    const device = {'brick': 50, 'empty': 0, 'old': 80};
    await r.syncDeviceBests(device.keys, (id) async => device[id]!);
    expect(store.saved['brick/$uid'], 50);
    expect(store.saved.containsKey('empty/$uid'), isFalse);
    expect(store.saved['old/$uid'], 90, reason: '서버가 더 높으면 그대로');
    expect(store.writes, 1);
  });

  test('기기 기록을 못 읽는 게임은 건너뛰고 나머지는 맞춘다', () async {
    final store = _FakeStore();
    final r = ScoreReporter(account: _FakeAccount(uid), store: store);
    await r.syncDeviceBests(['broken', 'brick'], (id) async {
      if (id == 'broken') throw Exception('storage blocked');
      return 40;
    });
    expect(store.saved['brick/$uid'], 40);
  });
}
