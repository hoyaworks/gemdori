import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/account.dart';
import 'package:gemdori/app/firebase_account.dart';

// 규칙 ① — 이미 로그인돼 있으면 발급하지 않고, 없을 때만 게스트를 발급한다 (Firebase 없이 확인)
void main() {
  const saved = (uid: 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf', isAnonymous: true);
  const issued = (uid: 'Nw1GuestAbCdEfGhIjKlMnOpQrSt', isAnonymous: true);

  test('이미 로그인돼 있으면 새로 발급하지 않는다', () async {
    var signIns = 0;
    final source = FirebaseAccountSource(
      restore: () async => saved,
      signInAnonymously: () async {
        signIns++;
        return issued;
      },
    );
    final a = await source.current();
    expect(a.id, saved.uid);
    expect(a.kind, AccountKind.guest);
    expect(signIns, 0);
  });

  test('로그인 기록이 없을 때만 게스트를 발급한다', () async {
    var signIns = 0;
    final source = FirebaseAccountSource(
      restore: () async => null,
      signInAnonymously: () async {
        signIns++;
        return issued;
      },
    );
    final a = await source.current();
    expect(a.id, issued.uid);
    expect(a.kind, AccountKind.guest);
    expect(signIns, 1);
  });

  test('여러 곳에서 동시에 물어도 발급은 한 번', () async {
    var signIns = 0;
    final source = FirebaseAccountSource(
      restore: () async => null,
      signInAnonymously: () async {
        signIns++;
        return issued;
      },
    );
    final both = await Future.wait([source.current(), source.current()]);
    expect(signIns, 1);
    expect(both[0].id, both[1].id);
  });

  test('Firebase 준비가 끝난 뒤에 로그인 상태를 본다', () async {
    final order = <String>[];
    final ready = Future<void>.delayed(Duration.zero, () => order.add('ready'));
    final source = FirebaseAccountSource(
      ready: ready,
      restore: () async {
        order.add('restore');
        return saved;
      },
    );
    await source.current();
    expect(order, ['ready', 'restore']);
  });

  test('발급에 실패하면 기억하지 않고 다음에 다시 시도한다', () async {
    var signIns = 0;
    final source = FirebaseAccountSource(
      restore: () async => null,
      signInAnonymously: () async {
        signIns++;
        if (signIns == 1) throw Exception('offline');
        return issued;
      },
    );
    await expectLater(source.current(), throwsException);
    final a = await source.current();
    expect(a.id, issued.uid);
    expect(signIns, 2);
  });

  test('익명이 아닌 로그인은 MEMBER 로 본다', () async {
    final source = FirebaseAccountSource(
      restore: () async => (uid: 'member-uid', isAnonymous: false),
    );
    final a = await source.current();
    expect(a.kind, AccountKind.member);
  });
}
