// ═══════════════════════════════════════════════════════════════════
//  best_score.dart — 기기에 저장하는 게임별 최고 점수
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임별 최고 점수를 기기에 남기고 읽는다
//  제외 사항 : 이 판의 점수를 기록해도 되는가 (각 게임 상태가 판단 — 벽돌깨기는 `BrickState.recordable`)
//              · 서버 랭킹 (다음 단계 — Firebase)
//
//  상세 설명 : 브라우저에서는 localStorage, 폰에서는 앱 전용 저장소에 들어간다
//    (shared_preferences 가 기기마다 알맞은 곳을 고른다).
//    브라우저 기록을 지우면 함께 사라진다 — 「이 기기의 기록」이라 그게 맞다.
//
//  주요 로직 : 키를 **게임 이름으로 나눈다** (`best.<gameId>`).
//    겜도리는 게임 모음이라, 게임이 늘어도 이 파일은 손대지 않는다.
//
//  주요 로직 : **넘었을 때만** 저장한다. 같은 점수는 새 기록이 아니다 —
//    같은 점수에 NEW 가 뜨면 기록의 의미가 흐려진다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

/// 게임별 최고 점수 저장소.
class BestScores {
  BestScores._(this._prefs);

  /// 저장소를 연다.
  /// 실패(브라우저 사생활 보호 모드 등)는 부르는 쪽이 받아 **기능만 끈다** — 기록은 곁가지다.
  static Future<BestScores> open() async =>
      BestScores._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static String _key(String gameId) => 'best.$gameId';

  /// 지금까지의 최고 점수. 기록이 없으면 0
  int best(String gameId) => _prefs.getInt(_key(gameId)) ?? 0;

  /// 이번 판 점수를 낸다 — 기록을 **넘었으면** 저장하고 true.
  Future<bool> submit(String gameId, int score) async {
    if (score <= best(gameId)) return false;
    await _prefs.setInt(_key(gameId), score);
    return true;
  }
}
