import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/account.dart';

// 계정 정보를 화면에 보일 모양 — 발급 전 · 게스트 · 회원
void main() {
  group('발급 전', () {
    test('아이디·닉네임은 — 로 보인다', () {
      const a = Account(kind: AccountKind.guest);
      expect(a.displayId, Account.empty);
      expect(a.displayNickname, Account.empty);
      expect(a.kindLabel, 'GUEST');
    });

    test('빈 문자열도 발급 전으로 본다', () {
      const a = Account(kind: AccountKind.guest, id: '', nickname: '');
      expect(a.displayId, Account.empty);
      expect(a.displayNickname, Account.empty);
    });

    test('자리표시 source 는 발급 전 게스트를 준다', () async {
      final a = await const PendingAccountSource().current();
      expect(a.kind, AccountKind.guest);
      expect(a.id, isNull);
    });
  });

  group('게스트', () {
    test('긴 익명 아이디는 앞 8자 + … 로 줄인다', () {
      const a = Account(kind: AccountKind.guest, id: 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf');
      expect(a.displayId, 'Xy7kQ2mN…');
    });

    test('8자 이하면 그대로', () {
      const a = Account(kind: AccountKind.guest, id: 'Xy7kQ2mN');
      expect(a.displayId, 'Xy7kQ2mN');
    });
  });

  group('회원', () {
    test('가입 아이디는 길어도 그대로 보인다', () {
      const a = Account(
        kind: AccountKind.member,
        id: 'gemdori.player@example.com',
        nickname: 'PLAYER1',
      );
      expect(a.displayId, 'gemdori.player@example.com');
      expect(a.displayNickname, 'PLAYER1');
      expect(a.kindLabel, 'MEMBER');
    });
  });
}
