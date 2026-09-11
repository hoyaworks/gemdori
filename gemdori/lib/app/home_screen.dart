import 'package:flutter/material.dart';

import '../games/brick/brick_game_screen.dart';
import 'best_score.dart';

// ═══════════════════════════════════════════════════════════════════
//  home_screen.dart — 게임 목록
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 목록을 보여주고 고른 게임 화면으로 넘긴다 · 게임별 최고 점수를 곁에 띄운다
//  제외 사항 : 게임 내용 (각 게임 폴더가 갖는다) · 점수 저장 (app/best_score.dart)
//
//  상세 설명
//    겜도리는 게임 하나짜리 앱이 아니라 '캐주얼 게임 모음'이다.
//    게임을 추가할 때 손대는 곳을 여기 한 곳으로 묶어 두었다.
//      1) lib/games/<게임이름>/ 폴더를 만들고
//      2) 아래 games 목록에 항목 하나를 추가한다 (id 는 그 게임 화면의 gameId)
//    화면 전환·목록 UI 는 건드릴 일이 없다.
//
//  주요 로직 : 최고 점수는 **처음 열 때와 게임에서 돌아왔을 때** 다시 읽는다 (2026-09-11).
//    방금 한 판에서 기록이 바뀌었을 수 있기 때문이다. 기록이 없으면(0) 아무것도 띄우지 않는다.
//
// ═══════════════════════════════════════════════════════════════════

/// 게임 목록 화면. 게임이 늘어나면 아래 목록에 항목만 추가한다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final List<_GameEntry> _games = [
    _GameEntry(
      id: BrickGameScreen.gameId,
      title: 'Brick Breaker',
      subtitle: 'Bounce the ball, break the bricks',
      icon: Icons.sports_tennis,
      builder: (_) => const BrickGameScreen(),
    ),
  ];

  /// 게임별 최고 점수 — 못 읽으면 비워 두고 표시만 안 한다
  Map<String, int> _best = const {};

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    try {
      final store = await BestScores.open();
      if (!mounted) return;
      setState(() => _best = {for (final g in _games) g.id: store.best(g.id)});
    } catch (_) {
      // 저장소를 못 열면 점수 표시만 빠진다
    }
  }

  Future<void> _open(_GameEntry g) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: g.builder));
    _loadBest(); // 방금 판에서 기록이 바뀌었을 수 있다
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'GEMDORI',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _games.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final g = _games[i];
          final best = _best[g.id] ?? 0;
          return Card(
            child: ListTile(
              leading: Icon(g.icon, size: 32),
              title: Text(g.title),
              subtitle: Text(g.subtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 최고 점수 — 글자(BEST) 대신 트로피 (아이콘 우선 규칙)
                  if (best > 0) ...[
                    const Icon(
                      Icons.emoji_events,
                      size: 18,
                      color: Color(0xFFFFD86B),
                    ),
                    const SizedBox(width: 4),
                    Text('$best'),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => _open(g),
            ),
          );
        },
      ),
    );
  }
}

class _GameEntry {
  _GameEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  /// 게임 이름 — 최고 점수를 찾는 키. 그 게임 화면의 `gameId` 와 같아야 한다
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}
