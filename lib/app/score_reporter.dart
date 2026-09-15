import 'package:flutter/widgets.dart';

import 'account.dart';

// ═══════════════════════════════════════════════════════════════════
//  score_reporter.dart — 점수를 서버 랭킹에 올린다
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임이 낸 점수를 **서버 기록보다 높을 때만** 내 랭킹 문서에 올린다
//              · 앱을 열 때 기기 최고 기록과 서버 기록을 한 번 맞춘다
//  제외 사항 : 서버 읽기·쓰기 자체 (firebase_ranking.dart) · 「이 판을 기록해도 되나」 (각 게임 상태)
//              · 랭킹 목록 보여 주기 (다음 단계) · 점수가 진짜인지 검증 (⑤ 단계)
//
//  상세 설명 : 계정당·게임당 **최고 점수 문서 1개**다 (2026-09-15). 한 사람이 랭킹을 도배하지 않는다.
//    게임 화면은 `ScoreReporterScope.maybeOf(context)` 로 이것을 찾아 부르기만 한다 —
//    없으면(테스트·Firebase 없는 실행) 조용히 아무것도 하지 않는다.
//
//  ⭐ 주요 로직 : **실패해도 게임을 멈추지 않는다.** 계정 확인·서버 읽기·쓰기 어디서 실패해도 false 로 끝난다.
//    놓친 기록은 **다음에 앱을 열 때** `syncDeviceBests` 가 기기 기록으로 다시 맞춘다 —
//    기기 기록과 게스트 계정은 같은 브라우저 저장 공간에 있어 둘이 함께 유지·삭제되기 때문에 가능한 방법이다.
//
//  주요 로직 : 올리기 전에 서버 기록을 **먼저 읽는다** — 보안 규칙이 「올라가기만」을 막고 있어
//    낮은 점수를 그냥 쓰면 거절 오류만 난다. 읽기 1번으로 쓸데없는 거절을 피한다.
//
// ═══════════════════════════════════════════════════════════════════

/// 서버 랭킹 저장소 — 화면·규칙 코드는 이것만 안다 (실제 구현 = firebase_ranking.dart)
abstract interface class RankingStore {
  /// 내 서버 기록. 없으면 null
  Future<int?> bestOf(String gameId, String uid);

  /// 내 기록을 이 점수로 올린다
  Future<void> save(String gameId, String uid, int score);
}

/// 점수 올리기
class ScoreReporter {
  ScoreReporter({required AccountSource account, required RankingStore store})
    : _account = account,
      _store = store;

  final AccountSource _account;
  final RankingStore _store;

  /// 이번 점수를 낸다 — 실제로 서버에 올렸으면 true
  Future<bool> report(String gameId, int score) async {
    if (score <= 0) return false;
    try {
      final uid = (await _account.current()).id;
      if (uid == null || uid.isEmpty) return false; // 아이디 발급 전·실패
      final server = await _store.bestOf(gameId, uid) ?? 0;
      if (score <= server) return false;
      await _store.save(gameId, uid, score);
      return true;
    } catch (_) {
      return false; // 네트워크·권한 실패 — 다음에 앱을 열 때 다시 맞춘다
    }
  }

  /// 앱을 열 때 — 기기 최고 기록이 서버보다 높으면 올린다 (지난번 전송 실패 보충)
  Future<void> syncDeviceBests(
    Iterable<String> gameIds,
    Future<int> Function(String gameId) deviceBest,
  ) async {
    for (final id in gameIds) {
      final int best;
      try {
        best = await deviceBest(id);
      } catch (_) {
        continue; // 기기 기록을 못 읽는 게임은 건너뛴다
      }
      await report(id, best);
    }
  }
}

/// 앱 전체에서 `ScoreReporter` 를 찾게 해 주는 자리 — main.dart 가 MaterialApp 바깥에 씌운다
class ScoreReporterScope extends InheritedWidget {
  const ScoreReporterScope({super.key, required this.reporter, required super.child});

  final ScoreReporter reporter;

  /// 없으면 null — 부르는 쪽은 「안 올린다」로 처리한다
  static ScoreReporter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ScoreReporterScope>()?.reporter;

  @override
  bool updateShouldNotify(ScoreReporterScope oldWidget) => reporter != oldWidget.reporter;
}
