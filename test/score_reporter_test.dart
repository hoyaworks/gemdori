import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/best_score.dart';
import 'package:gemdori/app/score_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// 점수 올리기 — 서버 기록보다 높을 때만 · 닉네임 사본 · 실패해도 멈추지 않음 · 앱 열 때 기기 기록 맞추기 · 순위

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('앱 열 때 기기 ↔ 서버 맞추기', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('기기가 높으면 서버에 올린다 · 기록 없는 게임은 건드리지 않는다', () async {
      final device = await BestScores.open();
      await device.submit('brick', 50, uid: uid);
      final store = FakeRankingStore();
      final r = ScoreReporter(account: FakeAccount(uid), store: store, nickname: () async => 'ME');
      await r.syncDeviceBests(['brick', 'empty'], BestScores.open);
      expect(store.docs['brick/$uid']!.score, 50);
      expect(store.docs['brick/$uid']!.nickname, 'ME');
      expect(store.docs.containsKey('empty/$uid'), isFalse);
    });

    test('서버가 높으면 기기를 서버 값으로 채운다 — 새 기기에서 로그인한 회원', () async {
      final store = FakeRankingStore()..put('brick', uid, 90);
      final r = ScoreReporter(account: FakeAccount(uid), store: store);
      await r.syncDeviceBests(['brick'], BestScores.open);
      expect((await BestScores.open()).best('brick', uid: uid), 90);
      expect(store.writes, 0);
    });

    test('주인 없는 기록(예전 기록)을 먼저 지금 계정으로 옮긴 뒤 맞춘다', () async {
      final device = await BestScores.open();
      await device.submit('brick', 40);
      final store = FakeRankingStore();
      final r = ScoreReporter(account: FakeAccount(uid), store: store);
      await r.syncDeviceBests(['brick'], BestScores.open);
      expect(store.docs['brick/$uid']!.score, 40);
      expect(device.best('brick'), 0, reason: '주인 없는 쪽은 지워진다');
      expect(device.best('brick', uid: uid), 40);
    });

    test('아이디가 없으면 아무것도 하지 않는다 — 주인 없는 기록도 그대로', () async {
      final device = await BestScores.open();
      await device.submit('brick', 40);
      final store = FakeRankingStore();
      await ScoreReporter(account: FakeAccount(null), store: store)
          .syncDeviceBests(['brick'], BestScores.open);
      expect(store.writes, 0);
      expect(device.best('brick'), 40);
    });

    test('서버를 못 읽으면 그 게임은 건너뛴다 — 오류 없이', () async {
      final device = await BestScores.open();
      await device.submit('brick', 40, uid: uid);
      final store = FakeRankingStore()..failRead = true;
      await ScoreReporter(account: FakeAccount(uid), store: store)
          .syncDeviceBests(['brick'], BestScores.open);
      expect(store.writes, 0);
    });
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
