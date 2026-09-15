import 'dart:math';

// ═══════════════════════════════════════════════════════════════════
//  nickname.dart — 닉네임 규칙 (한 곳)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 닉네임으로 쓸 수 있는 글자·길이를 판단하고, 게스트 기본 이름을 만든다
//  제외 사항 : 저장·변경 (player_profile.dart) · 입력 화면 (profile_screen.dart)
//
//  상세 설명 : 영문·숫자·`-`·`_` 만, 2~12자 (2026-09-15). 서비스 텍스트가 영어라 한글은 받지 않는다.
//    기본 이름은 `GUEST-4821` 처럼 숫자 4자리를 붙인다. **겹칠 수 있다** — 닉네임은 보여 주기용이고
//    사람을 가르는 것은 계정 uid 다. 겹치지 않게 막으려면 서버 검사가 필요해 지금은 하지 않는다.
//
//  ⚠️ 이 규칙은 **firestore.rules 의 validNickname 과 짝이다.** 한쪽만 바꾸면 저장이 거절된다.
//
// ═══════════════════════════════════════════════════════════════════

/// 닉네임 규칙
abstract final class Nickname {
  static const int minLength = 2;
  static const int maxLength = 12;

  /// 한 글자씩 받을 수 있는 글자 — 입력칸이 이것 말고는 아예 못 치게 막는다
  static final RegExp allowedChar = RegExp(r'[A-Za-z0-9_-]');

  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9_-]{2,12}$');

  /// 입력칸 아래 안내 문구
  static const String hint = 'A-Z  0-9  -  _   (2-12)';

  /// 닉네임으로 쓸 수 있는가
  static bool isValid(String value) => _pattern.hasMatch(value);

  /// 게스트 기본 이름 — `GUEST-0000` ~ `GUEST-9999`
  static String guest([Random? random]) =>
      'GUEST-${(random ?? Random()).nextInt(10000).toString().padLeft(4, '0')}';
}
