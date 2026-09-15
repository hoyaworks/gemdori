import 'dart:async';
import 'dart:math';

import 'account.dart';
import 'nickname.dart';
import 'score_reporter.dart';

// ═══════════════════════════════════════════════════════════════════
//  player_profile.dart — 내 닉네임 (없으면 만들고, 바꾸면 랭킹 사본까지)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱을 열 때 닉네임이 없으면 `GUEST-####` 를 만들어 저장한다 · 닉네임 바꾸기
//  제외 사항 : 글자 규칙 (nickname.dart) · 서버 읽기·쓰기 (firebase_profile.dart · firebase_ranking.dart)
//              · 입력 화면 (profile_screen.dart)
//
//  상세 설명 : 닉네임 원본은 `users/{uid}` 한 곳이다 (2026-09-15).
//    랭킹 문서에는 **사본**을 넣는다 — 랭킹 20줄을 그릴 때 사람마다 users 를 따로 읽지 않기 위해서다.
//    그래서 이름을 바꾸면 **원본을 먼저 고치고, 기록이 있는 게임의 랭킹 사본을 이어서 고친다.**
//
//  주요 로직 : 여러 곳이 동시에 물어도 만들기는 한 번만 돈다 · 실패(null)는 기억하지 않는다
//    (firebase_account.dart 와 같은 방식).
//
//  주요 로직 : 랭킹 사본 고치기가 일부 실패해도 이름 바꾸기는 성공으로 본다 — 원본은 바뀌었고,
//    사본은 다음에 기록을 올리거나 이름을 다시 바꿀 때 맞춰진다.
//
// ═══════════════════════════════════════════════════════════════════

/// 계정별 프로필 저장소 — 실제 구현 = firebase_profile.dart
abstract interface class ProfileStore {
  /// 저장된 닉네임. 없으면 null
  Future<String?> nicknameOf(String uid);

  Future<void> setNickname(String uid, String nickname);
}

/// 내 닉네임
class PlayerProfile {
  PlayerProfile({
    required AccountSource account,
    required ProfileStore profiles,
    required RankingStore rankings,
    required Iterable<String> gameIds,
    Random? random,
  }) : _account = account,
       _profiles = profiles,
       _rankings = rankings,
       _gameIds = List.unmodifiable(gameIds),
       _random = random ?? Random();

  final AccountSource _account;
  final ProfileStore _profiles;
  final RankingStore _rankings;
  final List<String> _gameIds;
  final Random _random;

  Future<String?>? _pending;

  /// 내 닉네임 — 없으면 게스트 이름을 만들어 저장한다. 못 구하면 null (다음에 물으면 다시 시도)
  Future<String?> nickname() {
    final running = _pending;
    if (running != null) return running;
    final next = _ensure();
    _pending = next;
    unawaited(
      next.then<void>((value) {
        if (value == null && identical(_pending, next)) _pending = null;
      }),
    );
    return next;
  }

  Future<String?> _ensure() async {
    try {
      final uid = await _uid();
      if (uid == null) return null;
      final saved = await _profiles.nicknameOf(uid);
      if (saved != null && Nickname.isValid(saved)) return saved;
      final made = Nickname.guest(_random);
      await _profiles.setNickname(uid, made);
      return made;
    } catch (_) {
      return null;
    }
  }

  /// 닉네임을 바꾼다 — 앞뒤 공백은 잘라 낸다. 규칙에 맞지 않거나 저장에 실패하면 false
  Future<bool> rename(String value) async {
    final name = value.trim();
    if (!Nickname.isValid(name)) return false;
    try {
      final uid = await _uid();
      if (uid == null) return false;
      await _profiles.setNickname(uid, name);
      _pending = Future.value(name);
      for (final id in _gameIds) {
        try {
          await _rankings.renameIn(id, uid, name);
        } catch (_) {
          // 사본은 다음에 기록을 올리거나 이름을 바꿀 때 맞춰진다
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _uid() async {
    final id = (await _account.current()).id;
    return (id == null || id.isEmpty) ? null : id;
  }
}
