import 'package:flutter/material.dart';

import '../games/brick/brick_game_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  game_catalog.dart — 겜도리에 들어 있는 게임 목록 (단 한 곳)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임마다 id·이름·설명·아이콘·화면을 한 줄로 적어 둔다
//  제외 사항 : 목록을 그리는 화면 (GAMES 탭 = games_tab.dart · RANKING 탭 = ranking_screen.dart)
//
//  상세 설명
//    게임을 추가할 때 손대는 곳은 여기 한 곳이다.
//      1) lib/games/<게임이름>/ 폴더를 만들고
//      2) 아래 gameCatalog 에 항목 하나를 추가한다 (id 는 그 게임 화면의 gameId)
//    GAMES 탭과 RANKING 탭이 **같은 목록을 읽으므로** 두 곳에 저절로 나타난다.
//
//  ⭐ 주요 로직 : 목록을 화면 밖으로 뺀 이유 (2026-09-15)
//    예전에는 홈 화면 안에 private 로 들어 있었다. RANKING 탭이 생기면서 그대로 두면
//    **목록을 두 번 적게 되고**, 한쪽만 고치면 「게임은 있는데 랭킹에는 없는」 상태가 된다.
//
//  ⚠️ id 는 최고 점수 저장 키이자 (다음 단계) 서버 랭킹 키다. **한 번 정하면 바꾸지 않는다** —
//    바꾸면 쌓인 기록과 연결이 끊긴다. 겹치지 않는지는 테스트가 지킨다.
//
// ═══════════════════════════════════════════════════════════════════

/// 게임 하나의 목록 정보
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  /// 게임 키 — 그 게임 화면의 `gameId` 와 같아야 한다
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// 게임 화면을 만든다
  final WidgetBuilder builder;
}

/// 게임 목록. 보여지는 순서도 이 순서다.
final List<GameEntry> gameCatalog = [
  GameEntry(
    id: BrickGameScreen.gameId,
    title: 'Brick Breaker',
    subtitle: 'Bounce the ball, break the bricks',
    icon: Icons.sports_tennis,
    builder: (_) => const BrickGameScreen(),
  ),
];
