import 'package:flutter/widgets.dart';

import 'account.dart';
import 'player_profile.dart';
import 'score_reporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  app_services.dart — 앱 전체가 함께 쓰는 서비스를 찾는 자리
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 계정 · 점수 올리기 · 닉네임 · 랭킹 저장소를 화면 어디서나 찾게 한다
//  제외 사항 : 각 서비스의 동작 (각 파일) · 무엇을 넣을지 (main.dart)
//
//  상세 설명 : main.dart 가 MaterialApp **바깥**에 한 번 씌운다 (2026-09-15) —
//    그래야 게임·랭킹처럼 새로 띄운 화면(route)에서도 찾을 수 있다.
//    예전의 `ScoreReporterScope`(점수 올리기 하나)를 서비스가 늘어 여기로 합쳤다.
//
//  주요 로직 : **없어도 화면이 돈다.** 테스트나 Firebase 없는 실행에서는 이것이 없거나 비어 있고,
//    화면은 계정=발급 전 게스트 · 점수·랭킹=「안 한다 / OFFLINE」로 처리한다.
//
// ═══════════════════════════════════════════════════════════════════

/// 앱 공용 서비스
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    this.account = const PendingAccountSource(),
    this.scores,
    this.profile,
    this.rankings,
    required super.child,
  });

  final AccountSource account;
  final ScoreReporter? scores;
  final PlayerProfile? profile;
  final RankingStore? rankings;

  /// 없으면 null
  static AppServices? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppServices>();

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      account != oldWidget.account ||
      scores != oldWidget.scores ||
      profile != oldWidget.profile ||
      rankings != oldWidget.rankings;
}
