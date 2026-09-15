// ═══════════════════════════════════════════════════════════════════
//  main.dart — 앱 진입점
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱 이름·테마를 정하고 홈(HomeScreen — 하단 탭 GAMES·RANKING·PROFILE)을 띄운다
//              · 앱을 열 때 Firebase 를 준비하고 계정 확인(없으면 게스트 발급)을 시작해 둔다
//              · 계정·점수 올리기·닉네임·랭킹 저장소를 앱 전체에 씌우고(AppServices),
//                닉네임이 없으면 만들고, 기기 기록과 서버 기록을 한 번 맞춘다
//  제외 사항 : 게임 내용 · 화면 전환 · 로그인 판단 (app/firebase_account.dart)
//
//  상세 설명 : 게임이 늘어나도 이 파일은 손대지 않는다.
//
//  ⭐ 주요 로직 : 게스트 발급 시점 = **앱을 처음 열 때** (2026-09-15 확정).
//    다만 **첫 화면을 기다리게 하지 않는다** — Firebase 준비와 발급은 뒤에서 돌고 화면은 바로 뜬다.
//    각 화면은 같은 확인을 기다렸다가 쓴다(발급·닉네임 만들기가 두 번 돌지 않는다).
//    네트워크가 없어 실패해도 게임은 그대로 할 수 있다 — 계정은 곁가지다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app_services.dart';
import 'app/best_score.dart';
import 'app/firebase_account.dart';
import 'app/firebase_profile.dart';
import 'app/firebase_ranking.dart';
import 'app/game_catalog.dart';
import 'app/home_screen.dart';
import 'app/player_profile.dart';
import 'app/score_reporter.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final account = FirebaseAccountSource(
    ready: Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  );
  final rankings = FirestoreRankingStore();
  final gameIds = [for (final g in gameCatalog) g.id];
  final profile = PlayerProfile(
    account: account,
    profiles: FirestoreProfileStore(),
    rankings: rankings,
    gameIds: gameIds,
  );
  final scores = ScoreReporter(account: account, store: rankings, nickname: profile.nickname);

  unawaited(account.current()); // 앱을 열 때 확인·발급을 시작해 둔다
  unawaited(profile.nickname()); // 닉네임이 없으면 GUEST-#### 를 만들어 둔다
  // 지난번에 못 올린 기록이 있으면 기기 최고 기록으로 맞춘다 — 계정 확인이 끝난 뒤에 돈다
  unawaited(
    scores.syncDeviceBests(gameIds, (id) async => (await BestScores.open()).best(id)),
  );

  runApp(
    AppServices(
      account: account,
      scores: scores,
      profile: profile,
      rankings: rankings,
      child: const GemDoriApp(),
    ),
  );
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
