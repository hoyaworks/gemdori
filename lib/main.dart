// ═══════════════════════════════════════════════════════════════════
//  main.dart — 앱 진입점
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱 이름·테마를 정하고 홈(HomeScreen — 하단 탭 GAMES·RANKING·PROFILE)을 띄운다
//  제외 사항 : 게임 내용 · 화면 전환
//
//  상세 설명 : 게임이 늘어나도 이 파일은 손대지 않는다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app/home_screen.dart';

void main() {
  runApp(const GemDoriApp());
}

class GemDoriApp extends StatelessWidget {
  const GemDoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GemDori',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6FC3FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
