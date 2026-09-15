import 'package:cloud_firestore/cloud_firestore.dart';

import 'player_profile.dart';

// ═══════════════════════════════════════════════════════════════════
//  firebase_profile.dart — 계정별 프로필(닉네임)을 Firestore 에 읽고 쓴다
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : `users/{uid}` 문서의 닉네임을 읽고 쓴다
//  제외 사항 : 없을 때 만들기·바꿀 때 랭킹 사본 맞추기 (player_profile.dart) · 권한 (firestore.rules)
//
//  상세 설명 : 필드는 `nickname` · `updatedAt`(서버 시각) 둘뿐이다 (2026-09-15).
//    이 문서는 **본인만 읽고 쓴다** — 다른 사람에게 보이는 이름은 랭킹 문서의 사본이다.
//
//  ⚠️ 경로·필드 이름은 firestore.rules 와 짝이다.
//
// ═══════════════════════════════════════════════════════════════════

/// Firestore 프로필 저장소
class FirestoreProfileStore implements ProfileStore {
  FirestoreProfileStore({FirebaseFirestore? db}) : _db = db;

  /// 넘기지 않으면 기본 DB — 계정 확인 뒤에만 불리므로 늦게 잡는다
  final FirebaseFirestore? _db;

  static const String users = 'users';

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      (_db ?? FirebaseFirestore.instance).collection(users).doc(uid);

  @override
  Future<String?> nicknameOf(String uid) async =>
      (await _doc(uid).get()).data()?['nickname'] as String?;

  @override
  Future<void> setNickname(String uid, String nickname) =>
      _doc(uid).set({'nickname': nickname, 'updatedAt': FieldValue.serverTimestamp()});
}
