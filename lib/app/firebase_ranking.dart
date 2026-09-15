import 'package:cloud_firestore/cloud_firestore.dart';

import 'score_reporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  firebase_ranking.dart — 랭킹 기록을 Firestore 에 읽고 쓴다
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : `rankings/{gameId}/scores/{uid}` 문서를 읽고 쓴다 · 상위 목록 · 내 순위 세기
//  제외 사항 : 올릴지 말지 판단 (score_reporter.dart) · 누가 무엇을 쓸 수 있나 (저장소 루트 firestore.rules)
//
//  상세 설명 : 문서 = 계정당·게임당 최고 점수 1개 (2026-09-15).
//    필드는 `score`(정수) · `updatedAt`(서버 시각) · `nickname`(닉네임 사본, 없을 수 있음).
//
//  ⭐ 주요 로직 : 시각은 **서버 시각(serverTimestamp)** 으로 넣는다 — 보안 규칙이 `request.time` 과 같은지 본다.
//    기기 시각을 넣으면 규칙에 막히고, 막지 않으면 시각을 조작할 수 있다.
//
//  주요 로직 : 점수는 `merge: true` 로 쓴다 — 닉네임을 못 구해 이름 없이 올려도 있던 사본을 지우지 않게.
//
//  주요 로직 : 내 순위는 **「나보다 높은 기록 수 + 1」** 을 세기(count)로 구한다 — 문서를 다 받지 않는다.
//    같은 점수는 같은 순위가 되어 목록의 순위 매기는 법(competitionRanks)과 맞는다.
//
//  ⚠️ 경로 이름(rankings · scores)과 필드 이름은 **firestore.rules 와 짝이다.** 한쪽만 바꾸면 전부 거절된다.
//
// ═══════════════════════════════════════════════════════════════════

/// Firestore 랭킹 저장소
class FirestoreRankingStore implements RankingStore {
  FirestoreRankingStore({FirebaseFirestore? db}) : _db = db;

  /// 넘기지 않으면 기본 DB — Firebase 준비가 끝난 뒤(계정 확인 뒤)에만 불리므로 늦게 잡는다
  final FirebaseFirestore? _db;

  static const String rankings = 'rankings';
  static const String scores = 'scores';

  CollectionReference<Map<String, dynamic>> _col(String gameId) =>
      (_db ?? FirebaseFirestore.instance).collection(rankings).doc(gameId).collection(scores);

  DocumentReference<Map<String, dynamic>> _doc(String gameId, String uid) => _col(gameId).doc(uid);

  @override
  Future<int?> bestOf(String gameId, String uid) async {
    final snap = await _doc(gameId, uid).get();
    return (snap.data()?['score'] as num?)?.toInt();
  }

  @override
  Future<void> save(String gameId, String uid, int score, {String? nickname}) =>
      _doc(gameId, uid).set({
        'score': score,
        'updatedAt': FieldValue.serverTimestamp(),
        'nickname': ?nickname,
      }, SetOptions(merge: true));

  @override
  Future<List<RankingEntry>> top(String gameId, {required int limit}) async {
    final q = await _col(gameId).orderBy('score', descending: true).limit(limit).get();
    return [
      for (final d in q.docs)
        if (d.data()['score'] is num)
          RankingEntry(
            uid: d.id,
            score: (d.data()['score'] as num).toInt(),
            nickname: d.data()['nickname'] as String?,
          ),
    ];
  }

  @override
  Future<int> countAbove(String gameId, int score) async {
    final agg = await _col(gameId).where('score', isGreaterThan: score).count().get();
    return agg.count ?? 0;
  }

  @override
  Future<void> renameIn(String gameId, String uid, String nickname) async {
    final ref = _doc(gameId, uid);
    if (!(await ref.get()).exists) return; // 기록 없는 게임
    await ref.update({'nickname': nickname, 'updatedAt': FieldValue.serverTimestamp()});
  }
}
