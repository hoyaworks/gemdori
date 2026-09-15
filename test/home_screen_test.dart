import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/account.dart';
import 'package:gemdori/app/app_services.dart';
import 'package:gemdori/app/game_catalog.dart';
import 'package:gemdori/app/home_screen.dart';
import 'package:gemdori/app/player_profile.dart';
import 'package:gemdori/app/profile_screen.dart';
import 'package:gemdori/app/ranking_screen.dart';
import 'package:gemdori/games/brick/brick_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// 게임 목록(한 곳) · 홈 탭 전환 · RANKING 화면 · PROFILE 표시·닉네임 바꾸기
void main() {
  const myUid = 'Xy7kQ2mN9pLr4sTu1vWz3aBc5dEf';

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

  group('홈 탭 (서비스 없음)', () {
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

    testWidgets('RANKING 탭 → 게임을 누르면 랭킹 화면 — 서비스가 없으면 OFFLINE', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('RANKING'));
      await tester.pumpAndSettle();

      // GAMES 탭 본문은 가려져 있으므로 이름은 RANKING 목록 한 곳에서만 보인다
      final first = gameCatalog.first;
      expect(find.text(first.title), findsOneWidget);

      await tester.tap(find.text(first.title));
      await tester.pumpAndSettle();
      expect(find.text('OFFLINE'), findsOneWidget);
    });

    testWidgets('PROFILE 탭 — 발급 전 게스트로 보이고 연필 버튼이 없다', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();

      expect(find.text('GUEST'), findsOneWidget);
      expect(find.text('ID'), findsOneWidget);
      // 닉네임 · 아이디 두 칸 모두 발급 전
      expect(find.text(Account.empty), findsNWidgets(2));
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });

  group('랭킹 화면 (가짜 서비스)', () {
    final game = gameCatalog.first;

    Future<void> pumpRanking(WidgetTester tester, FakeRankingStore store) async {
      await tester.pumpWidget(
        AppServices(
          account: FakeAccount(myUid),
          rankings: store,
          child: MaterialApp(home: GameRankingScreen(game: game)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('기록이 없으면 NO RECORDS YET', (tester) async {
      await pumpRanking(tester, FakeRankingStore());
      expect(find.text('NO RECORDS YET'), findsOneWidget);
    });

    testWidgets('높은 순 · 같은 점수 같은 순위 · 내 줄은 YOU · 닉네임 없으면 GUEST', (tester) async {
      final store = FakeRankingStore()
        ..put(game.id, 'u1', 100, nickname: 'ACE')
        ..put(game.id, myUid, 80, nickname: 'ME')
        ..put(game.id, 'u3', 80);
      await pumpRanking(tester, store);

      expect(find.text('ACE'), findsOneWidget);
      expect(find.text('ME'), findsOneWidget);
      expect(find.text('GUEST'), findsOneWidget);
      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2), reason: '80점 두 명은 둘 다 2위');
      expect(find.textContaining('#'), findsNothing, reason: '내가 목록 안이면 아래 줄이 없다');
    });

    testWidgets('내가 20위 밖이면 아래에 내 순위 한 줄', (tester) async {
      final store = FakeRankingStore();
      for (var i = 0; i < 25; i++) {
        store.put(game.id, 'other$i', 1000 - i, nickname: 'P$i');
      }
      // 내 점수는 순위 숫자(1~20)와 겹치지 않는 값으로 — 겹치면 글자 찾기가 두 곳을 잡는다
      store.put(game.id, myUid, 42, nickname: 'ME');
      await pumpRanking(tester, store);

      expect(find.text('#26'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('PROFILE 닉네임 (가짜 서비스)', () {
    testWidgets('닉네임이 보이고, 연필로 바꾸면 새 이름이 보인다', (tester) async {
      final account = FakeAccount(myUid);
      final profiles = FakeProfileStore()..names[myUid] = 'GUEST-0001';
      final profile = PlayerProfile(
        account: account,
        profiles: profiles,
        rankings: FakeRankingStore(),
        gameIds: [for (final g in gameCatalog) g.id],
      );
      await tester.pumpWidget(
        AppServices(
          account: account,
          profile: profile,
          child: const MaterialApp(home: Scaffold(body: ProfileTab())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('GUEST-0001'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'NEW NAME!');
      await tester.pump();
      // 허용 글자 말고는 입력되지 않는다
      expect(find.text('NEWNAME'), findsOneWidget);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      expect(find.text('NEWNAME'), findsOneWidget);
      expect(profiles.names[myUid], 'NEWNAME');
    });
  });
}
