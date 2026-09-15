import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'account.dart';

// ═══════════════════════════════════════════════════════════════════
//  firebase_account.dart — Firebase 익명 인증으로 「지금 계정」을 준다
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 앱을 열 때 로그인 상태를 확인하고, **없을 때만** 게스트(익명 계정)를 발급한다
//  제외 사항 : 계정을 화면에 보일 모양 (account.dart) · 구글 로그인·계정 연결 (④ 단계)
//              · Firebase 준비 시점 결정 (main.dart)
//
//  상세 설명 : 화면은 `AccountSource` 만 안다. 이 파일이 그 실제 구현이다 (2026-09-15).
//    게스트 = 사람이 아니라 「저장 공간 하나」다 — 같은 브라우저·같은 주소면 같은 게스트,
//    브라우저를 바꾸거나 사이트 데이터를 지우면 새 게스트다 (공식 문서 확인 · docs gd_main.md).
//
//  ⭐ 주요 로직 : **이미 로그인돼 있으면 발급하지 않는다** (규칙 ①).
//    웹은 저장된 로그인 상태를 IndexedDB 에서 읽어 오는 데 시간이 걸린다.
//    그래서 `currentUser` 를 바로 보지 않고 **첫 로그인 상태 알림(authStateChanges)을 받은 뒤** 판단한다.
//    바로 보면 복원 전이라 비어 있어 **열 때마다 새 게스트가 생긴다.**
//
//  ⭐ 주요 로직 : 여러 곳이 동시에 물어도 **확인·발급은 한 번만** 돈다 (진행 중인 것을 같이 기다린다).
//    단 **실패는 기억하지 않는다** — 네트워크가 없어 실패했으면 다음에 물을 때 다시 시도한다.
//
//  주요 로직 : Firebase 호출은 **바꿔 끼울 수 있게** 받는다 (restore · signInAnonymously).
//    규칙 ①을 Firebase 없이 테스트로 못박기 위해서다 — 앱에서는 기본값(실제 Firebase)이 쓰인다.
//
// ═══════════════════════════════════════════════════════════════════

/// 계정 판단에 필요한 로그인 정보만 — Firebase `User` 를 화면 쪽으로 흘리지 않는다
typedef AuthIdentity = ({String uid, bool isAnonymous});

/// Firebase 익명 인증으로 계정을 주는 곳
class FirebaseAccountSource implements AccountSource {
  FirebaseAccountSource({
    Future<Object?>? ready,
    Future<AuthIdentity?> Function()? restore,
    Future<AuthIdentity> Function()? signInAnonymously,
  }) : _ready = ready,
       _restore = restore ?? _restoreFromFirebase,
       _signIn = signInAnonymously ?? _signInToFirebase;

  /// Firebase 준비(initializeApp) — 이것이 끝난 뒤에 로그인 상태를 본다
  final Future<Object?>? _ready;

  /// 저장돼 있던 로그인 상태. 없으면 null
  final Future<AuthIdentity?> Function() _restore;

  /// 게스트 발급
  final Future<AuthIdentity> Function() _signIn;

  /// 진행 중이거나 끝난 확인 — 같이 기다려 발급이 두 번 돌지 않게
  Future<Account>? _pending;

  @override
  Future<Account> current() {
    final running = _pending;
    if (running != null) return running;
    final next = _resolve();
    _pending = next;
    // 실패는 기억하지 않는다 — 다음에 물으면 다시 시도
    unawaited(
      next.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_pending, next)) _pending = null;
        },
      ),
    );
    return next;
  }

  Future<Account> _resolve() async {
    await _ready;
    final identity = await _restore() ?? await _signIn();
    return Account(
      kind: identity.isAnonymous ? AccountKind.guest : AccountKind.member,
      // 회원은 ④ 단계에서 가입 아이디(메일)로 바꾼다. 지금은 익명뿐이다
      id: identity.uid,
    );
  }

  static Future<AuthIdentity?> _restoreFromFirebase() async {
    final user = await FirebaseAuth.instance.authStateChanges().first;
    return user == null ? null : (uid: user.uid, isAnonymous: user.isAnonymous);
  }

  static Future<AuthIdentity> _signInToFirebase() async {
    final user = (await FirebaseAuth.instance.signInAnonymously()).user!;
    return (uid: user.uid, isAnonymous: user.isAnonymous);
  }
}
