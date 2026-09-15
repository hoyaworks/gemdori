// ═══════════════════════════════════════════════════════════════════
//  best_score_test.dart — 최고 점수 저장 · 기록 자격
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 저장소가 「넘었을 때만」 남기는지, 어떤 판을 기록에서 빼는지 확인한다
//  제외 사항 : 화면 표시 (끝난 화면·홈 목록 — 위젯 테스트는 두지 않는다)
//
//  주요 로직 : 실제 기기 저장소 대신 **메모리 저장소**로 돌린다
//    (`SharedPreferences.setMockInitialValues`). 테스트마다 비워서 서로 섞이지 않게 한다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/best_score.dart';
import 'package:gemdori/games/brick/brick_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  storeTests();
  recordableTests();
}

void storeTests() {
  group('최고 점수 저장소', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('기록이 없으면 0', () async {
      final s = await BestScores.open();
      expect(s.best('brick'), 0);
    });

    test('넘으면 저장하고 새 기록으로 알린다', () async {
      final s = await BestScores.open();
      expect(await s.submit('brick', 30), isTrue);
      expect(s.best('brick'), 30);
    });

    test('못 넘거나 같으면 저장하지 않는다', () async {
      final s = await BestScores.open();
      await s.submit('brick', 30);
      expect(await s.submit('brick', 20), isFalse);
      expect(await s.submit('brick', 30), isFalse, reason: '같은 점수는 새 기록이 아니다');
      expect(s.best('brick'), 30);
    });

    test('0점은 기록이 아니다', () async {
      final s = await BestScores.open();
      expect(await s.submit('brick', 0), isFalse);
    });

    test('게임마다 따로 쌓인다', () async {
      final s = await BestScores.open();
      await s.submit('brick', 30);
      expect(s.best('other'), 0);
    });
  });

  group('계정별 기기 기록', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('계정마다 따로 쌓인다 — 한 기기에서 A·B 가 번갈아 써도 섞이지 않는다', () async {
      final s = await BestScores.open();
      expect(await s.submit('brick', 30, uid: 'A'), isTrue);
      expect(s.best('brick', uid: 'B'), 0);
      expect(await s.submit('brick', 10, uid: 'B'), isTrue, reason: 'B 에게는 첫 기록');
      expect(s.best('brick', uid: 'A'), 30);
    });

    test('주인 없는 기록(예전 기록)은 계정으로 읽을 때도 보인다', () async {
      final s = await BestScores.open();
      await s.submit('brick', 40); // 계정을 모를 때
      expect(s.best('brick', uid: 'A'), 40);
      expect(await s.submit('brick', 40, uid: 'A'), isFalse, reason: '같은 점수는 새 기록이 아니다');
    });

    test('옮기면 그 계정 것이 되고 주인 없는 쪽은 지워진다 — 높은 값만 남는다', () async {
      final s = await BestScores.open();
      await s.submit('brick', 40);
      await s.submit('brick', 50, uid: 'A');
      await s.adoptUnassigned('A', ['brick']);
      expect(s.best('brick', uid: 'A'), 50);
      expect(s.best('brick'), 0);
      expect(s.best('brick', uid: 'B'), 0, reason: '옮긴 뒤에는 다른 계정에 안 보인다');
    });

    test('끌어올리기는 높을 때만', () async {
      final s = await BestScores.open();
      await s.submit('brick', 30, uid: 'A');
      await s.raiseTo('brick', 20, uid: 'A');
      expect(s.best('brick', uid: 'A'), 30);
      await s.raiseTo('brick', 60, uid: 'A');
      expect(s.best('brick', uid: 'A'), 60);
    });

    test('계정 기록 지우기 — 게스트를 삭제할 때', () async {
      final s = await BestScores.open();
      await s.submit('brick', 30, uid: 'A');
      await s.submit('brick', 20, uid: 'B');
      await s.removeAccount('A', ['brick']);
      expect(s.best('brick', uid: 'A'), 0);
      expect(s.best('brick', uid: 'B'), 20);
    });
  });
}

void recordableTests() {
  group('점수를 기록해도 되는 판인가', () {
    BrickState make() =>
        BrickState(fieldSize: const Size(400, 600), refWidth: 400);

    test('보통 판은 기록한다', () {
      expect(make().recordable, isTrue);
    });

    test('샘플 스테이지는 기록하지 않는다 — 시험장이다', () {
      final s = make()..debugLoadSampleStage();
      expect(s.recordable, isFalse);
    });

    test('치트를 한 번이라도 쓴 판은 기록하지 않는다', () {
      expect((make()..debugGoToStage(5)).recordable, isFalse);
      expect((make()..debugGameOver()).recordable, isFalse);
      expect((make()..debugClearStage()).recordable, isFalse);
    });

    test('다시 시작하면 치트 흔적이 지워진다', () {
      final s = make()
        ..debugGoToStage(5)
        ..restart();
      expect(s.recordable, isTrue);
    });
  });
}
