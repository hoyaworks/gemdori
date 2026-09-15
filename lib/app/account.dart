// ═══════════════════════════════════════════════════════════════════
//  account.dart — 지금 이 기기를 쓰는 사람의 계정 정보
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 계정 종류(GUEST / MEMBER) · 아이디 · 닉네임과, 그것을 화면에 보일 모양
//  제외 사항 : 아이디 발급·로그인 (firebase_account.dart) · 화면 (profile_screen.dart)
//
//  상세 설명 : 화면은 `AccountSource` 에게 「지금 계정」을 묻기만 한다.
//    앱에서는 `FirebaseAccountSource`(firebase_account.dart)가 그 자리에 들어가고 (2026-09-15),
//    `PendingAccountSource` 는 Firebase 없이 도는 테스트용 자리다 — 화면은 둘을 구분하지 않는다.
//
//  ⭐ 주요 로직 : 발급 전에는 **기기에서 임시 아이디를 따로 만들지 않는다** (2026-09-15).
//    만들면 나중에 Firebase 아이디와 두 개가 생겨 「어느 쪽이 내 아이디인가」가 흐려진다.
//    대신 `—` 로 보여 「아직 없다」를 그대로 드러낸다.
//
//  ⭐ 주요 로직 : 게스트 아이디는 **앞 8자만** 보인다.
//    익명 아이디는 28자 무작위 문자열이라 통째로 띄우면 읽을 수도 없고 화면만 차지한다.
//    회원 아이디(가입 아이디)는 사람이 정한 값이라 그대로 보인다.
//
// ═══════════════════════════════════════════════════════════════════

/// 계정 종류
enum AccountKind { guest, member }

/// 계정 정보 한 벌
class Account {
  const Account({required this.kind, this.id, this.nickname});

  final AccountKind kind;

  /// 게스트 = 자동 발급 아이디 · 회원 = 가입 아이디. 아직 발급 전이면 null
  final String? id;
  final String? nickname;

  /// 게스트 아이디를 화면에 보일 글자 수
  static const int shortIdLength = 8;

  /// 값이 없을 때 보이는 표시
  static const String empty = '—';

  /// 화면에 보일 아이디
  String get displayId {
    final v = id;
    if (v == null || v.isEmpty) return empty;
    if (kind == AccountKind.member || v.length <= shortIdLength) return v;
    return '${v.substring(0, shortIdLength)}…';
  }

  /// 화면에 보일 닉네임
  String get displayNickname {
    final v = nickname;
    return (v == null || v.isEmpty) ? empty : v;
  }

  /// 계정 종류 배지 글자
  String get kindLabel => switch (kind) {
    AccountKind.guest => 'GUEST',
    AccountKind.member => 'MEMBER',
  };
}

/// 「지금 계정」을 알려 주는 곳 — 화면은 이것만 안다
abstract interface class AccountSource {
  Future<Account> current();
}

/// Firebase 없이 쓰는 자리(테스트) — 아이디 발급 전의 게스트를 돌려준다
class PendingAccountSource implements AccountSource {
  const PendingAccountSource();

  @override
  Future<Account> current() async => const Account(kind: AccountKind.guest);
}
