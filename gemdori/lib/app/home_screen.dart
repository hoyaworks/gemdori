import 'package:flutter/material.dart';

import '../games/brick/brick_game_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  home_screen.dart — 게임 목록
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 목록을 보여주고 고른 게임 화면으로 넘긴다
//  제외 사항 : 게임 내용 (각 게임 폴더가 갖는다)
//
//  상세 설명
//    겜도리는 게임 하나짜리 앱이 아니라 '캐주얼 게임 모음'이다.
//    게임을 추가할 때 손대는 곳을 여기 한 곳으로 묶어 두었다.
//      1) lib/games/<게임이름>/ 폴더를 만들고
//      2) 아래 games 목록에 항목 하나를 추가한다
//    화면 전환·목록 UI 는 건드릴 일이 없다.
//
// ═══════════════════════════════════════════════════════════════════

/// 게임 목록 화면. 게임이 늘어나면 아래 목록에 항목만 추가한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = <_GameEntry>[
      _GameEntry(
        title: 'Brick Breaker',
        subtitle: 'Bounce the ball, break the bricks',
        icon: Icons.sports_tennis,
        builder: (_) => const BrickGameScreen(),
      ),
    ];

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
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final g = games[i];
          return Card(
            child: ListTile(
              leading: Icon(g.icon, size: 32),
              title: Text(g.title),
              subtitle: Text(g.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: g.builder)),
            ),
          );
        },
      ),
    );
  }
}

class _GameEntry {
  _GameEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}
