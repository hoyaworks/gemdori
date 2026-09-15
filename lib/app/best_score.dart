// ═══════════════════════════════════════════════════════════════════
//  best_score.dart — 기기에 저장하는 게임별 최고 점수 (계정별)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 계정별·게임별 최고 점수를 기기에 남기고 읽는다
//  제외 사항 : 이 판의 점수를 기록해도 되는가 (각 게임 상태가 판단 — 벽돌깨기는 `BrickState.recordable`)
//              · 서버 랭킹 올리기·기기와 서버 기록 맞추기 (score_reporter.dart)
//
//  상세 설명 : 브라우저에서는 localStorage, 폰에서는 앱 전용 저장소에 들어간다
//    (shared_preferences 가 기기마다 알맞은 곳을 고른다).
//    브라우저 기록을 지우면 함께 사라진다 — 「이 기기의 기록」이라 그게 맞다.
//
//  ⭐ 주요 로직 : 키를 **계정과 게임으로 나눈다** (`best.<uid>.<gameId>` · 2026-09-15).
//    한 기기에서 회원 A·B 와 게스트가 번갈아 쓰면 기록이 섞이고, 섞인 기록이
//    「앱 열 때 보충」 규칙으로 **남의 이름으로 랭킹에 올라가기** 때문이다.
//
//  ⭐ 주요 로직 : 계정을 모를 때(예전 기록 · 계정 발급 전 오프라인 판)는 **주인 없는 기록**(`best.<gameId>`)에 둔다.
//    계정이 생기면 `adoptUnassigned` 로 그 계정에 옮긴다. 옮기기 전이라도 계정 기록을 읽을 때
//    **주인 없는 기록도 같이 봐서** 높은 값을 준다 — 앱을 열자마자 🏆 가 0 으로 보이는 일이 없게.
//
//  주요 로직 : **넘었을 때만** 저장한다. 같은 점수는 새 기록이 아니다 —
//    같은 점수에 NEW 가 뜨면 기록의 의미가 흐려진다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 계정별·게임별 최고 점수 저장소.
class BestScores {
  BestScores._(this._prefs);

  /// 저장소를 연다.
  /// 실패(브라우저 사생활 보호 모드 등)는 부르는 쪽이 받아 **기능만 끈다** — 기록은 곁가지다.
  static Future<BestScores> open() async =>
      BestScores._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// 주인 없는 기록 — 예전(계정별로 나누기 전) 키와 같다
  static String _unassignedKey(String gameId) => 'best.$gameId';

  static String _key(String? uid, String gameId) =>
      uid == null || uid.isEmpty ? _unassignedKey(gameId) : 'best.$uid.$gameId';

  int _read(String key) => _prefs.getInt(key) ?? 0;

  /// 지금까지의 최고 점수. 기록이 없으면 0.
  /// 계정을 넘기면 **그 계정 기록과 주인 없는 기록 중 높은 값**
  int best(String gameId, {String? uid}) {
    final own = _read(_key(uid, gameId));
    if (uid == null || uid.isEmpty) return own;
    return max(own, _read(_unassignedKey(gameId)));
  }

  /// 이번 판 점수를 낸다 — 기록을 **넘었으면** 저장하고 true.
  Future<bool> submit(String gameId, int score, {String? uid}) async {
    if (score <= best(gameId, uid: uid)) return false;
    await _prefs.setInt(_key(uid, gameId), score);
    return true;
  }

  /// 기록을 이 점수까지 끌어올린다 (서버 기록이 더 높을 때) — 낮으면 그대로
  Future<void> raiseTo(String gameId, int score, {required String uid}) async {
    if (score > _read(_key(uid, gameId))) await _prefs.setInt(_key(uid, gameId), score);
  }

  /// 주인 없는 기록을 이 계정으로 옮긴다 — 높은 값만 남기고 주인 없는 쪽은 지운다
  Future<void> adoptUnassigned(String uid, Iterable<String> gameIds) async {
    for (final id in gameIds) {
      final loose = _read(_unassignedKey(id));
      if (loose <= 0) continue;
      await raiseTo(id, loose, uid: uid);
      await _prefs.remove(_unassignedKey(id));
    }
  }

  /// 이 계정의 기기 기록을 지운다 (게스트를 삭제할 때)
  Future<void> removeAccount(String uid, Iterable<String> gameIds) async {
    for (final id in gameIds) {
      await _prefs.remove(_key(uid, id));
    }
  }
}
