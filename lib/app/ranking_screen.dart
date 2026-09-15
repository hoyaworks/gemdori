import 'package:flutter/material.dart';

import 'game_catalog.dart';

// ═══════════════════════════════════════════════════════════════════
//  ranking_screen.dart — RANKING 탭 : 게임별 랭킹으로 들어가는 목록
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 목록을 보여주고, 고른 게임의 랭킹 화면으로 넘긴다
//  제외 사항 : 점수 기록·순위 계산 (다음 단계 — Firebase) · 목록 내용 (game_catalog.dart)
//
//  상세 설명 : 게임이 하나뿐이어도 **목록 단계를 둔다** (2026-09-15) —
//    게임이 늘었을 때 화면 구성을 다시 뜯지 않기 위해서다.
//    게임별 랭킹 화면은 지금은 **자리만** 있다. 순위는 서버가 붙은 뒤에 채운다.
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

/// 게임 하나의 랭킹 화면 — 지금은 빈 자리
class GameRankingScreen extends StatelessWidget {
  const GameRankingScreen({super.key, required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(game.title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.leaderboard, size: 64, color: muted),
            const SizedBox(height: 12),
            Text(
              'COMING SOON',
              style: TextStyle(color: muted, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }
}
