import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/score_reporter.dart';

import 'fakes.dart';

// 점수 올리기 — 서버 기록보다 높을 때만 · 닉네임 사본 · 실패해도 멈추지 않음 · 앱 열 때 기기 기록 맞추기 · 순위

void main() {
  const uid = 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf';

  test('서버 기록이 없으면 올린다', () async {
    final store = FakeRankingStore();
    final r = ScoreReporter(account: FakeAccount(uid), store: store);
    expect(await r.report('brick', 30), isTrue);
    expect(store.docs['brick/$uid']!.score, 30);
  });

  test('서버 기록보다 높을 때만 올린다 — 같거나 낮으면 쓰지 않는다', () async {
    final store = FakeRankingStore()..put('brick', uid, 30);
    final r = ScoreReporter(account: FakeAccount(uid), store: store);
    expect(await r.report('brick', 20), isFalse);
    expect(await r.report('brick', 30), isFalse, reason: '같은 점수는 새 기록이 아니다');
    expect(store.writes, 0);
    expect(await r.report('brick', 31), isTrue);
    expect(store.docs['brick/$uid']!.score, 31);
  });

  test('올릴 때 닉네임 사본을 같이 넣는다', () async {
    final store = FakeRankingStore();
    final r = ScoreReporter(account: FakeAccount(uid), store: store, nickname: () async => 'PLAYER1');
    await r.report('brick', 30);
    expect(store.docs['brick/$uid']!.nickname, 'PLAYER1');
  });

  test('닉네임을 못 구해도 점수는 올린다', () async {
    final store = FakeRankingStore();
    final r = ScoreReporter(
      account: FakeAccount(uid),
      store: store,
      nickname: () async => throw Exception('offline'),
    );
    expect(await r.report('brick', 30), isTrue);
    expect(store.docs['brick/$uid']!.nickname, isNull);
  });

  test('0점은 올리지 않는다 — 계정도 묻지 않는다', () async {
    final account = FakeAccount(uid);
    final store = FakeRankingStore();
    final r = ScoreReporter(account: account, store: store);
    expect(await r.report('brick', 0), isFalse);
    expect(account.asked, 0);
    expect(store.reads, 0);
  });

  test('아이디가 없으면(발급 전·실패) 올리지 않는다', () async {
    final store = FakeRankingStore();
    final r = ScoreReporter(account: FakeAccount(null), store: store);
    expect(await r.report('brick', 30), isFalse);
    expect(store.reads, 0);
  });

  test('계정 확인이나 서버 읽기가 실패해도 오류 없이 false', () async {
    final r1 = ScoreReporter(account: FakeAccount(uid, fail: true), store: FakeRankingStore());
    expect(await r1.report('brick', 30), isFalse);

    final store = FakeRankingStore()..failRead = true;
    final r2 = ScoreReporter(account: FakeAccount(uid), store: store);
    expect(await r2.report('brick', 30), isFalse);
    expect(store.writes, 0);
  });

  test('앱을 열 때 기기 기록이 서버보다 높은 게임만 올린다', () async {
    final store = FakeRankingStore()..put('old', uid, 90);
    final r = ScoreReporter(account: FakeAccount(uid), store: store);
    const device = {'brick': 50, 'empty': 0, 'old': 80};
    await r.syncDeviceBests(device.keys, (id) async => device[id]!);
    expect(store.docs['brick/$uid']!.score, 50);
    expect(store.docs.containsKey('empty/$uid'), isFalse);
    expect(store.docs['old/$uid']!.score, 90, reason: '서버가 더 높으면 그대로');
    expect(store.writes, 1);
  });

  test('기기 기록을 못 읽는 게임은 건너뛰고 나머지는 맞춘다', () async {
    final store = FakeRankingStore();
    final r = ScoreReporter(account: FakeAccount(uid), store: store);
    await r.syncDeviceBests(['broken', 'brick'], (id) async {
      if (id == 'broken') throw Exception('storage blocked');
      return 40;
    });
    expect(store.docs['brick/$uid']!.score, 40);
  });

  group('순위 매기기', () {
    test('같은 점수는 같은 순위, 다음 순위는 그만큼 건너뛴다', () {
      expect(competitionRanks([50, 40, 40, 30]), [1, 2, 2, 4]);
      expect(competitionRanks([10, 10, 10]), [1, 1, 1]);
    });

    test('빈 목록', () {
      expect(competitionRanks([]), isEmpty);
    });
  });
}
