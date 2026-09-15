import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/player_profile.dart';

import 'fakes.dart';

// 내 닉네임 — 없으면 한 번만 만든다 · 바꾸면 원본과 기록 있는 게임의 랭킹 사본을 고친다

void main() {
  const uid = 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf';

  PlayerProfile make({
    FakeAccount? account,
    FakeProfileStore? profiles,
    FakeRankingStore? rankings,
    List<String> games = const ['brick', 'other'],
  }) => PlayerProfile(
    account: account ?? FakeAccount(uid),
    profiles: profiles ?? FakeProfileStore(),
    rankings: rankings ?? FakeRankingStore(),
    gameIds: games,
  );

  test('저장된 닉네임이 있으면 그대로 쓴다', () async {
    final profiles = FakeProfileStore()..names[uid] = 'SAVED1';
    final p = make(profiles: profiles);
    expect(await p.nickname(), 'SAVED1');
    expect(profiles.writes, 0);
  });

  test('없으면 GUEST-#### 를 만들어 저장한다 — 동시에 물어도 한 번만', () async {
    final profiles = FakeProfileStore();
    final p = make(profiles: profiles);
    final both = await Future.wait([p.nickname(), p.nickname()]);
    expect(both[0], matches(RegExp(r'^GUEST-\d{4}$')));
    expect(both[1], both[0]);
    expect(profiles.writes, 1);
    expect(profiles.names[uid], both[0]);
  });

  test('아이디가 없으면 null', () async {
    expect(await make(account: FakeAccount(null)).nickname(), isNull);
  });

  test('실패하면 null 이고, 기억하지 않아 다음에 다시 시도한다', () async {
    final profiles = FakeProfileStore()..fail = true;
    final p = make(profiles: profiles);
    expect(await p.nickname(), isNull);
    profiles.fail = false;
    expect(await p.nickname(), matches(RegExp(r'^GUEST-\d{4}$')));
  });

  test('규칙에 안 맞는 이름으로는 바꾸지 않는다', () async {
    final profiles = FakeProfileStore()..names[uid] = 'SAVED1';
    final p = make(profiles: profiles);
    expect(await p.rename('A'), isFalse);
    expect(await p.rename('with space'), isFalse);
    expect(profiles.names[uid], 'SAVED1');
  });

  test('바꾸면 원본 + 기록이 있는 게임의 랭킹 사본만 고친다 · 앞뒤 공백은 잘라 낸다', () async {
    final profiles = FakeProfileStore()..names[uid] = 'SAVED1';
    final rankings = FakeRankingStore()..put('brick', uid, 30, nickname: 'SAVED1');
    final p = make(profiles: profiles, rankings: rankings);

    expect(await p.rename('  NEWNAME '), isTrue);
    expect(profiles.names[uid], 'NEWNAME');
    expect(rankings.docs['brick/$uid']!.nickname, 'NEWNAME');
    expect(rankings.docs['brick/$uid']!.score, 30, reason: '점수는 그대로');
    expect(rankings.docs.containsKey('other/$uid'), isFalse, reason: '기록 없는 게임은 만들지 않는다');
    expect(await p.nickname(), 'NEWNAME');
  });

  test('원본 저장에 실패하면 false', () async {
    final profiles = FakeProfileStore()..fail = true;
    expect(await make(profiles: profiles).rename('NEWNAME'), isFalse);
  });
}
