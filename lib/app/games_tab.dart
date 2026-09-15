import 'package:flutter/material.dart';

import 'app_services.dart';
import 'best_score.dart';
import 'game_catalog.dart';

// ═══════════════════════════════════════════════════════════════════
//  games_tab.dart — GAMES 탭 : 게임 목록
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 목록을 보여주고 고른 게임 화면으로 넘긴다 · 게임별 최고 점수를 곁에 띄운다
//  제외 사항 : 목록 내용 (game_catalog.dart) · 점수 저장 (best_score.dart) · 탭 틀 (home_screen.dart)
//
//  상세 설명 : 2026-09-15 홈이 탭 구성으로 바뀌면서 홈 화면에서 목록 부분만 떼어 왔다.
//    🏆 칸은 **이 기기의 내 최고 기록**이다 — RANKING 탭(여러 사람 순위)과 역할이 다르다.
//
//  주요 로직 : 최고 점수는 **처음 열 때와 게임에서 돌아왔을 때** 다시 읽는다 (2026-09-11).
//    방금 한 판에서 기록이 바뀌었을 수 있기 때문이다. 기록이 없으면 **0 으로 띄운다** —
//    칸이 비어 있으면 「점수 기록이 있는 게임인지」부터 헷갈린다.
//
//  주요 로직 : 게임은 **맨 위 Navigator 로** 띄운다 — 하단 탭이 가려져 게임이 화면 전체를 쓴다.
//
// ═══════════════════════════════════════════════════════════════════

/// GAMES 탭 본문
class GamesTab extends StatefulWidget {
  const GamesTab({super.key});

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  /// 게임별 최고 점수 — 기록이 없거나 못 읽으면 0 으로 보인다
  Map<String, int> _best = const {};

  /// 점수 칸 폭 — 이름·설명 칸보다 좁게 고정한다 (점수 자릿수가 늘어도 칸이 흔들리지 않게)
  static const double _scoreCellWidth = 80;

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    // 🏆 는 **지금 계정의** 기록이다 (2026-09-15) — 계정을 3초 안에 못 받으면 주인 없는 기록만 보인다
    final account = AppServices.maybeOf(context)?.account;
    String? uid;
    try {
      uid = (await account?.current().timeout(const Duration(seconds: 3)))?.id;
    } catch (_) {
      // 계정을 몰라도 점수 칸은 띄운다
    }
    try {
      final store = await BestScores.open();
      if (!mounted) return;
      setState(() => _best = {for (final g in gameCatalog) g.id: store.best(g.id, uid: uid)});
    } catch (_) {
      // 저장소를 못 열면 점수 표시만 빠진다
    }
  }

  Future<void> _open(GameEntry g) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: g.builder));
    _loadBest(); // 방금 판에서 기록이 바뀌었을 수 있다
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: gameCatalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final g = gameCatalog[i];
        final best = _best[g.id] ?? 0;
        return Card(
          child: ListTile(
            leading: Icon(g.icon, size: 32),
            title: Text(g.title),
            subtitle: Text(g.subtitle),
            // [게임 이름·설명 | 🏆 최고 점수 >] — 점수는 **좁은 칸으로 따로 뗀다** (2026-09-11).
            //   이름이 먼저 읽히고, > 는 화면 오른쪽 끝에 두는 관례를 지킨다.
            //   > 를 점수 칸 앞에 두면 점수 칸이 따로 누르는 버튼처럼 보인다.
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1,
                  height: 36,
                  color: Theme.of(context).dividerColor,
                ),
                SizedBox(
                  width: _scoreCellWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 글자(BEST) 대신 트로피 — 아이콘 우선 규칙
                      const Icon(
                        Icons.emoji_events,
                        size: 18,
                        color: Color(0xFFFFD86B),
                      ),
                      const SizedBox(width: 4),
                      Text('$best'),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _open(g),
          ),
        );
      },
    );
  }
}
