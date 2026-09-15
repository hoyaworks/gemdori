import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/account.dart';
import 'package:gemdori/app/game_catalog.dart';
import 'package:gemdori/app/home_screen.dart';
import 'package:gemdori/games/brick/brick_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 게임 목록(한 곳) · 홈 탭 전환 · RANKING 상세 · PROFILE 발급 전 표시
void main() {
  group('게임 목록', () {
    test('id 가 비어 있지 않고 서로 겹치지 않는다 — 점수 저장·랭킹 키라서', () {
      final ids = gameCatalog.map((g) => g.id).toList();
      expect(ids, isNotEmpty);
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('벽돌깨기가 목록에 있고 id 가 게임 화면의 gameId 와 같다', () {
      expect(gameCatalog.any((g) => g.id == BrickGameScreen.gameId), isTrue);
    });
  });

  group('홈 탭', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('처음은 GAMES 탭 — 게임 목록이 보인다', (tester) async {
      await pumpHome(tester);
      expect(find.text('GAMES'), findsOneWidget);
      expect(find.text('RANKING'), findsOneWidget);
      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.text(gameCatalog.first.subtitle), findsOneWidget);
    });

    testWidgets('RANKING 탭 → 게임을 누르면 그 게임 랭킹 화면', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('RANKING'));
      await tester.pumpAndSettle();

      // GAMES 탭 본문은 가려져 있으므로 이름은 RANKING 목록 한 곳에서만 보인다
      final first = gameCatalog.first;
      expect(find.text(first.title), findsOneWidget);

      await tester.tap(find.text(first.title));
      await tester.pumpAndSettle();
      expect(find.text('COMING SOON'), findsOneWidget);
    });

    testWidgets('PROFILE 탭 — 발급 전 게스트로 보인다', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();

      expect(find.text('GUEST'), findsOneWidget);
      expect(find.text('ID'), findsOneWidget);
      // 닉네임 · 아이디 두 칸 모두 발급 전
      expect(find.text(Account.empty), findsNWidgets(2));
    });
  });
}
