import 'package:flutter/material.dart';

import 'account.dart';
import 'app_services.dart';
import 'game_catalog.dart';
import 'score_reporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  ranking_screen.dart — RANKING 탭 : 게임 목록 → 게임별 랭킹
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 목록을 보여주고, 고른 게임의 TOP 20 과 내 순위를 보여준다
//  제외 사항 : 점수 올리기 (score_reporter.dart) · 서버 읽기 (firebase_ranking.dart) · 목록 내용 (game_catalog.dart)
//
//  상세 설명 : 게임이 하나뿐이어도 **목록 단계를 둔다** (2026-09-15) —
//    게임이 늘었을 때 화면 구성을 다시 뜯지 않기 위해서다.
//    게임별 화면 = 높은 점수 순 20줄 · 같은 점수는 같은 순위 · 내 줄은 색과 `YOU` 로 표시 ·
//    내가 20위 밖이면 **아래에 내 순위 한 줄**을 따로 둔다. 닉네임이 없는 기록은 `GUEST` 로 보인다.
//
//  주요 로직 : **계정 확인을 먼저 기다린 뒤** 목록을 읽는다 — 계정 확인이 Firebase 준비를 기다리므로,
//    앱을 열자마자 이 화면에 들어와도 준비 전에 서버를 부르지 않는다.
//
//  주요 로직 : 읽기에 실패하거나 서비스가 없으면 `OFFLINE` — 새로고침 버튼으로 다시 읽는다.
//
//  주요 로직 : 탭 아이콘·빈 화면 아이콘은 **순위표(leaderboard)** 로 쓴다.
//    트로피는 GAMES 탭에서 「내 최고 기록」 표시로 이미 쓰고 있어, 같이 쓰면 둘이 섞여 읽힌다.
//
// ═══════════════════════════════════════════════════════════════════

/// RANKING 탭 본문
class RankingTab extends StatelessWidget {
  const RankingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: gameCatalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final g = gameCatalog[i];
        return Card(
          child: ListTile(
            leading: Icon(g.icon, size: 32),
            title: Text(g.title),
            trailing: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.leaderboard), Icon(Icons.chevron_right)],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GameRankingScreen(game: g)),
            ),
          ),
        );
      },
    );
  }
}

/// 게임 하나의 랭킹 화면
class GameRankingScreen extends StatefulWidget {
  const GameRankingScreen({super.key, required this.game});

  final GameEntry game;

  /// 보여 줄 줄 수
  static const int topCount = 20;

  @override
  State<GameRankingScreen> createState() => _GameRankingScreenState();
}

/// 한 번 읽어 온 랭킹
class _RankingView {
  const _RankingView({required this.top, this.myUid, this.myBest, this.myRank});

  final List<RankingEntry> top;
  final String? myUid;

  /// 내가 목록 밖일 때만 채운다
  final int? myBest;
  final int? myRank;
}

class _GameRankingScreenState extends State<GameRankingScreen> {
  RankingStore? _store;
  AccountSource _account = const PendingAccountSource();
  bool _started = false;

  _RankingView? _view;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppServices.maybeOf(context);
    _store = services?.rankings;
    _account = services?.account ?? const PendingAccountSource();
    _load();
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _failed = false;
      _view = null;
    });
    try {
      String? uid;
      try {
        uid = (await _account.current()).id;
      } catch (_) {
        // 내 계정을 몰라도 목록은 보여 준다
      }
      final gameId = widget.game.id;
      final top = await store.top(gameId, limit: GameRankingScreen.topCount);
      int? myBest;
      int? myRank;
      if (uid != null && !top.any((e) => e.uid == uid)) {
        myBest = await store.bestOf(gameId, uid);
        if (myBest != null) myRank = await store.countAbove(gameId, myBest) + 1;
      }
      if (!mounted) return;
      setState(() => _view = _RankingView(top: top, myUid: uid, myBest: myBest, myRank: myRank));
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.game.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'REFRESH', onPressed: _load),
        ],
      ),
      body: _failed
          ? const _Notice(icon: Icons.cloud_off, text: 'OFFLINE')
          : view == null
          ? const Center(child: CircularProgressIndicator())
          : view.top.isEmpty
          ? const _Notice(icon: Icons.leaderboard, text: 'NO RECORDS YET')
          : _list(view),
      bottomNavigationBar: (!_failed && view?.myRank != null) ? _MyRankBar(view: view!) : null,
    );
  }

  Widget _list(_RankingView view) {
    final ranks = competitionRanks([for (final e in view.top) e.score]);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: view.top.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = view.top[i];
          return _RankRow(
            rank: ranks[i],
            name: e.nickname ?? 'GUEST',
            score: e.score,
            mine: e.uid == view.myUid,
          );
        },
      ),
    );
  }
}

/// 랭킹 한 줄
class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.name, required this.score, required this.mine});

  final int rank;
  final String name;
  final int score;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: mine ? scheme.primaryContainer : null,
      child: ListTile(
        leading: _RankBadge(rank: rank),
        title: Text(name),
        subtitle: mine ? const Text('YOU') : null,
        trailing: Text(
          '$score',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 순위 숫자 — 1·2·3위만 메달 색
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  static const _medals = {1: Color(0xFFFFD86B), 2: Color(0xFFC9D1D9), 3: Color(0xFFD89A6B)};

  @override
  Widget build(BuildContext context) {
    final medal = _medals[rank];
    return CircleAvatar(
      radius: 18,
      backgroundColor: medal ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        '$rank',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: medal != null ? Colors.black87 : null,
        ),
      ),
    );
  }
}

/// 목록 밖 내 순위 — 화면 아래에 붙는다
class _MyRankBar extends StatelessWidget {
  const _MyRankBar({required this.view});

  final _RankingView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        color: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Text('#${view.myRank}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            const Text('YOU'),
            const Spacer(),
            Text('${view.myBest}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// 빈 화면 안내 — 아이콘 + 한 줄
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: muted),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: muted, letterSpacing: 2)),
        ],
      ),
    );
  }
}
