import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/nickname.dart';

// 닉네임 규칙 — firestore.rules 의 validNickname 과 같은 판단이어야 한다

void main() {
  test('영문·숫자·-·_ 2~12자는 쓸 수 있다', () {
    for (final ok in ['AB', 'ab', 'GUEST-4821', 'Player_12', 'ABCDEFGHIJKL', '12', 'a-_']) {
      expect(Nickname.isValid(ok), isTrue, reason: ok);
    }
  });

  test('길이·글자가 벗어나면 쓸 수 없다', () {
    for (final bad in ['', 'A', 'ABCDEFGHIJKLM', 'with space', '한글이름', 'a.b', 'emoji😀', ' AB']) {
      expect(Nickname.isValid(bad), isFalse, reason: bad);
    }
  });

  test('게스트 기본 이름은 GUEST-숫자4자리이고 규칙에 맞는다', () {
    final random = Random(7);
    for (var i = 0; i < 50; i++) {
      final name = Nickname.guest(random);
      expect(name, matches(RegExp(r'^GUEST-\d{4}$')));
      expect(Nickname.isValid(name), isTrue);
    }
  });

  test('한 글자씩 받는 허용 글자는 규칙과 같다', () {
    expect(Nickname.allowedChar.hasMatch('A'), isTrue);
    expect(Nickname.allowedChar.hasMatch('-'), isTrue);
    expect(Nickname.allowedChar.hasMatch(' '), isFalse);
    expect(Nickname.allowedChar.hasMatch('가'), isFalse);
  });
}
