import 'account.dart';
import 'best_score.dart';

// ═══════════════════════════════════════════════════════════════════
//  score_reporter.dart — 점수를 서버 랭킹에 올린다 · 랭킹 저장소 약속
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임이 낸 점수를 **서버 기록보다 높을 때만** 내 랭킹 문서에 올린다
//              · 앱을 열 때 지금 계정의 기기 기록과 서버 기록을 양쪽으로 맞춘다
//              · 랭킹 저장소가 지킬 약속(RankingStore)과 순위 매기는 법(competitionRanks)
//  제외 사항 : 서버 읽기·쓰기 자체 (firebase_ranking.dart) · 「이 판을 기록해도 되나」 (각 게임 상태)
//              · 랭킹 화면 (ranking_screen.dart) · 점수가 진짜인지 검증 (⑤ 단계)
//
//  상세 설명 : 계정당·게임당 **최고 점수 문서 1개**다 (2026-09-15). 한 사람이 랭킹을 도배하지 않는다.
//    게임 화면은 `AppServices.maybeOf(context)?.scores` 로 이것을 찾아 부르기만 한다 —
//    없으면(테스트·Firebase 없는 실행) 조용히 아무것도 하지 않는다.
//
//  ⭐ 주요 로직 : **실패해도 게임을 멈추지 않는다.** 계정 확인·서버 읽기·쓰기 어디서 실패해도 false 로 끝난다.
//    놓친 기록은 **다음에 앱을 열 때** `syncDeviceBests` 가 기기 기록으로 다시 맞춘다 —
//    기기 기록과 게스트 계정은 같은 브라우저 저장 공간에 있어 둘이 함께 유지·삭제되기 때문에 가능한 방법이다.
//
//  주요 로직 : 올리기 전에 서버 기록을 **먼저 읽는다** — 보안 규칙이 「올라가기만」을 막고 있어
//    낮은 점수를 그냥 쓰면 거절 오류만 난다. 읽기 1번으로 쓸데없는 거절을 피한다.
//
//  주요 로직 : 올릴 때 **닉네임 사본을 같이 넣는다** — 닉네임을 못 구해도 점수는 올린다(이름 없이).
//
// ═══════════════════════════════════════════════════════════════════

/// 랭킹 한 줄
class RankingEntry {
  const RankingEntry({required this.uid, required this.score, this.nickname});

  final String uid;
  final int score;

  /// 닉네임 사본 — 없으면 화면이 `GUEST` 로 보인다
  final String? nickname;
}

/// 서버 랭킹 저장소 — 화면·규칙 코드는 이것만 안다 (실제 구현 = firebase_ranking.dart)
abstract interface class RankingStore {
  /// 내 서버 기록. 없으면 null
  Future<int?> bestOf(String gameId, String uid);

  /// 내 기록을 이 점수로 올린다 (닉네임 사본을 함께)
  Future<void> save(String gameId, String uid, int score, {String? nickname});

  /// 높은 점수 순으로 limit 줄
  Future<List<RankingEntry>> top(String gameId, {required int limit});

  /// 이 점수보다 높은 기록 수 — 내 순위 = 이 값 + 1
  Future<int> countAbove(String gameId, int score);

  /// 내 랭킹 문서의 닉네임 사본만 바꾼다. 기록이 없는 게임이면 아무것도 하지 않는다
  Future<void> renameIn(String gameId, String uid, String nickname);
}

/// 같은 점수는 같은 순위다 — 50·40·40·30 → 1·2·2·4. 점수는 **높은 순**으로 넘긴다
List<int> competitionRanks(List<int> scoresDesc) {
  final ranks = <int>[];
  for (var i = 0; i < scoresDesc.length; i++) {
    final same = i > 0 && scoresDesc[i] == scoresDesc[i - 1];
    ranks.add(same ? ranks[i - 1] : i + 1);
  }
  return ranks;
}

/// 점수 올리기
class ScoreReporter {
  ScoreReporter({
    required AccountSource account,
    required RankingStore store,
    Future<String?> Function()? nickname,
  }) : _account = account,
       _store = store,
       _nickname = nickname;

  final AccountSource _account;
  final RankingStore _store;

  /// 올릴 때 넣을 닉네임 — 없으면 이름 없이 올린다
  final Future<String?> Function()? _nickname;

  /// 이번 점수를 낸다 — 실제로 서버에 올렸으면 true
  Future<bool> report(String gameId, int score) async {
    if (score <= 0) return false;
    try {
      final uid = (await _account.current()).id;
      if (uid == null || uid.isEmpty) return false; // 아이디 발급 전·실패
      final server = await _store.bestOf(gameId, uid) ?? 0;
      if (score <= server) return false;
      await _store.save(gameId, uid, score, nickname: await _nicknameOrNull());
      return true;
    } catch (_) {
      return false; // 네트워크·권한 실패 — 다음에 앱을 열 때 다시 맞춘다
    }
  }

  /// 앱을 열 때 — 지금 계정의 기기 기록과 서버 기록을 **양쪽으로** 맞춘다 (2026-09-15)
  ///   · 주인 없는 기기 기록(예전 기록·계정 발급 전 판)을 먼저 지금 계정으로 옮긴다
  ///   · 기기가 높으면 서버에 올린다 (지난번 전송 실패 보충)
  ///   · 서버가 높으면 기기를 서버 값으로 채운다 (새 기기에서 로그인한 회원의 🏆·NEW 가 틀리지 않게)
  Future<void> syncDeviceBests(
    Iterable<String> gameIds,
    Future<BestScores> Function() openDevice,
  ) async {
    try {
      final uid = (await _account.current()).id;
      if (uid == null || uid.isEmpty) return;
      final device = await openDevice();
      await device.adoptUnassigned(uid, gameIds);
      for (final id in gameIds) {
        final int? server;
        try {
          server = await _store.bestOf(id, uid);
        } catch (_) {
          continue; // 서버를 못 읽는 게임은 건너뛴다 — 다음에 열 때 다시
        }
        final local = device.best(id, uid: uid);
        if (server != null && server > local) {
          await device.raiseTo(id, server, uid: uid);
        } else if (local > (server ?? 0)) {
          try {
            await _store.save(id, uid, local, nickname: await _nicknameOrNull());
          } catch (_) {
            // 다음에 열 때 다시
          }
        }
      }
    } catch (_) {
      // 계정·기기 저장소를 못 열면 이번에는 건너뛴다
    }
  }

  Future<String?> _nicknameOrNull() async {
    try {
      return await _nickname?.call();
    } catch (_) {
      return null;
    }
  }
}
