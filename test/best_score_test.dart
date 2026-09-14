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
