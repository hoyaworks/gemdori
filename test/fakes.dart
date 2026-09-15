import 'package:gemdori/app/account.dart';
import 'package:gemdori/app/player_profile.dart';
import 'package:gemdori/app/score_reporter.dart';

// 테스트용 가짜 서비스 — Firebase 없이 계정·랭킹·프로필 동작을 흉내 낸다 (이 파일은 테스트가 아니다)

class FakeAccount implements AccountSource {
  FakeAccount(this.id, {this.fail = false});

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

class FakeRankingStore implements RankingStore {
  /// 키 = '게임/uid'
  final Map<String, RankingEntry> docs = {};
  int reads = 0;
  int writes = 0;
  bool failRead = false;

  String key(String gameId, String uid) => '$gameId/$uid';

  void put(String gameId, String uid, int score, {String? nickname}) =>
      docs[key(gameId, uid)] = RankingEntry(uid: uid, score: score, nickname: nickname);

  @override
  Future<int?> bestOf(String gameId, String uid) async {
    reads++;
    if (failRead) throw Exception('offline');
    return docs[key(gameId, uid)]?.score;
  }

  @override
  Future<void> save(String gameId, String uid, int score, {String? nickname}) async {
    writes++;
    final old = docs[key(gameId, uid)];
    put(gameId, uid, score, nickname: nickname ?? old?.nickname);
  }

  @override
  Future<List<RankingEntry>> top(String gameId, {required int limit}) async {
    if (failRead) throw Exception('offline');
    final list = [
      for (final e in docs.entries)
        if (e.key.startsWith('$gameId/')) e.value,
    ]..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  @override
  Future<int> countAbove(String gameId, int score) async => [
    for (final e in docs.entries)
      if (e.key.startsWith('$gameId/') && e.value.score > score) e,
  ].length;

  @override
  Future<void> renameIn(String gameId, String uid, String nickname) async {
    final old = docs[key(gameId, uid)];
    if (old == null) return;
    writes++;
    put(gameId, uid, old.score, nickname: nickname);
  }
}

class FakeProfileStore implements ProfileStore {
  final Map<String, String> names = {};
  int writes = 0;
  bool fail = false;

  @override
  Future<String?> nicknameOf(String uid) async {
    if (fail) throw Exception('offline');
    return names[uid];
  }

  @override
  Future<void> setNickname(String uid, String nickname) async {
    if (fail) throw Exception('offline');
    writes++;
    names[uid] = nickname;
  }
}
