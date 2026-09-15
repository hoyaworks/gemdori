// ═══════════════════════════════════════════════════════════════════
//  main.dart — 앱 진입점
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱 이름·테마를 정하고 홈(HomeScreen — 하단 탭 GAMES·RANKING·PROFILE)을 띄운다
//              · 앱을 열 때 Firebase 를 준비하고 계정 확인(없으면 게스트 발급)을 시작해 둔다
//  제외 사항 : 게임 내용 · 화면 전환 · 로그인 판단 (app/firebase_account.dart)
//
//  상세 설명 : 게임이 늘어나도 이 파일은 손대지 않는다.
//
//  ⭐ 주요 로직 : 게스트 발급 시점 = **앱을 처음 열 때** (2026-09-15 확정).
//    다만 **첫 화면을 기다리게 하지 않는다** — Firebase 준비와 발급은 뒤에서 돌고 화면은 바로 뜬다.
//    PROFILE 탭은 같은 확인을 기다렸다가 아이디를 그린다(발급이 두 번 돌지 않는다).
//    네트워크가 없어 실패해도 게임은 그대로 할 수 있다 — 계정은 곁가지다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/account.dart';
import 'app/firebase_account.dart';
import 'app/home_screen.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final account = FirebaseAccountSource(
    ready: Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  );
  unawaited(account.current()); // 앱을 열 때 확인·발급을 시작해 둔다 — 결과는 PROFILE 탭이 받아 간다
  runApp(GemDoriApp(accountSource: account));
}

class GemDoriApp extends StatelessWidget {
  const GemDoriApp({super.key, this.accountSource = const PendingAccountSource()});

  /// 계정 정보를 주는 곳 — 앱에서는 Firebase, 테스트에서는 기본값(발급 전 게스트)
  final AccountSource accountSource;

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
      home: HomeScreen(accountSource: accountSource),
    );
  }
}
