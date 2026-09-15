import 'package:flutter/material.dart';

import 'games_tab.dart';
import 'profile_screen.dart';
import 'ranking_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  home_screen.dart — 홈 : 하단 탭 3개 (GAMES · RANKING · PROFILE)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱 제목과 하단 탭을 두고, 고른 탭의 본문을 띄운다
//  제외 사항 : 탭 본문 (games_tab.dart · ranking_screen.dart · profile_screen.dart)
//              · 게임 목록 (game_catalog.dart) · 계정·랭킹 서비스 (app_services.dart)
//
//  상세 설명 : 2026-09-15 게임 목록 한 장이던 홈을 탭 구성으로 바꿨다.
//    게임 모음이 「점수 기록·랭킹·계정을 갖춘 서비스」로 가는 첫 틀이다.
//    탭 이름은 영어, 아이콘을 앞세운다 (서비스 텍스트 규칙).
//
//  주요 로직 : 탭 본문은 **IndexedStack 으로 한꺼번에 들고 있는다.**
//    탭을 오갈 때마다 새로 만들면 스크롤 위치가 풀리고, 점수·계정을 매번 다시 읽는다.
//
//  주요 로직 : 게임·랭킹 상세는 맨 위 Navigator 로 띄워 **하단 탭을 가린다** —
//    게임은 화면 전체를 써야 하고, 상세는 뒤로가기 한 번에 탭으로 돌아온다.
//
// ═══════════════════════════════════════════════════════════════════

/// 홈 화면 — 하단 탭 틀
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

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
      body: IndexedStack(
        index: _tab,
        children: const [GamesTab(), RankingTab(), ProfileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'GAMES',
          ),
          // 트로피가 아니라 순위표 — 트로피는 GAMES 탭의 「내 최고 기록」 표시다
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'RANKING',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'PROFILE',
          ),
        ],
      ),
    );
  }
}
