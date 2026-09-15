import 'package:cloud_firestore/cloud_firestore.dart';

import 'score_reporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  firebase_ranking.dart — 랭킹 기록을 Firestore 에 읽고 쓴다
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : `rankings/{gameId}/scores/{uid}` 문서 하나를 읽고 쓴다
//  제외 사항 : 올릴지 말지 판단 (score_reporter.dart) · 누가 무엇을 쓸 수 있나 (저장소 루트 firestore.rules)
//
//  상세 설명 : 문서 = 계정당·게임당 최고 점수 1개 (2026-09-15).
//    필드는 `score`(정수) · `updatedAt`(서버 시각) 둘뿐이다. 닉네임은 다음 단계에서 붙는다.
//
//  ⭐ 주요 로직 : 시각은 **서버 시각(serverTimestamp)** 으로 넣는다 — 보안 규칙이 `request.time` 과 같은지 본다.
//    기기 시각을 넣으면 규칙에 막히고, 막지 않으면 시각을 조작할 수 있다.
//
//  주요 로직 : `merge: true` 로 쓴다 — 나중에 붙을 닉네임 같은 다른 필드를 점수 올릴 때 지우지 않게.
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

  DocumentReference<Map<String, dynamic>> _doc(String gameId, String uid) =>
      (_db ?? FirebaseFirestore.instance)
          .collection(rankings)
          .doc(gameId)
          .collection(scores)
          .doc(uid);

  @override
  Future<int?> bestOf(String gameId, String uid) async {
    final snap = await _doc(gameId, uid).get();
    return (snap.data()?['score'] as num?)?.toInt();
  }

  @override
  Future<void> save(String gameId, String uid, int score) => _doc(gameId, uid).set(
    {'score': score, 'updatedAt': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
  );
}
