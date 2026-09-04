// ═══════════════════════════════════════════════════════════════════
//  brick_state_test.dart — 게임 규칙 테스트
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 화면을 띄우지 않고 BrickState 만 돌려서 규칙을 확인한다
//  제외 사항 : 화면·입력 (위젯 테스트는 두지 않는다)
//
//  상세 설명 — 테스트 묶음
//    ballTests()          공 이동과 벽 반사
//    paddleTests()        패들 이동 · 반사각
//    paddleTunnelTests()  빠른 공이 패들을 뚫지 않는가 (2026-09-02 실제로 났던 문제)
//    brickTests()         벽돌 배치 · 내구도 · 충돌 · 점수
//    progressTests()      발사 · 목숨 · 게임오버 · 클리어 · 스테이지
//
//  주요 로직 : 판정을 느슨하게 고칠 때는 반대쪽 테스트(정말 벗어나면 놓치는가)도 함께 둔다.
//    안 그러면 아무 데서나 튕기는 쪽으로 조용히 망가진다.
//
//  주요 로직 : 발사 각도가 무작위이므로 Random 을 주입해 결과를 고정한다.
//    무작위를 그대로 두면 테스트가 어쩌다 한 번 실패하는, 가장 다루기 힘든 형태가 된다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/games/brick/brick_state.dart';
import 'package:gemdori/games/brick/item.dart';

/// 공이 날아가는 중인 상태를 바로 만든다.
BrickState playing({
  required Offset ballPos,
  required Offset ballVelocity,
  double paddleX = 200,
}) =>
    BrickState(
      fieldSize: const Size(400, 600),
      status: GameStatus.playing,
      ballPos: ballPos,
      ballVelocity: ballVelocity,
      ballRadius: 8,
      paddleX: paddleX,
    );

void main() {
  ballTests();
  paddleTests();
  paddleTunnelTests();
  brickTests();
  progressTests();
  finishedTests();
  stageTests();
  wallHugTests();
  gapTests();
  sampleStageTests();
  multiBallTests();
}

void ballTests() {
  group('공', () {
    test('속도 × 시간 만큼 움직인다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(100, 50),
      );
      s.update(0.5);
      expect(s.ballPos.dx, closeTo(250, 0.001));
      expect(s.ballPos.dy, closeTo(325, 0.001));
    });

    // 2026-09-03 : 벽에 붙여 세우지 않고 **넘어간 만큼 되꺾는다**.
    //   50px 를 가다 42px 지점(벽면)에서 꺾이므로 8px 를 되돌아온 자리에 선다.
    test('왼쪽 벽에 닿으면 오른쪽으로 튕긴다', () {
      final s = playing(
        ballPos: const Offset(10, 300),
        ballVelocity: const Offset(-100, 0),
      );
      s.update(0.5);
      expect(s.ballPos.dx, 56, reason: '벽면 8 에서 되꺾여 48 만큼 더 간다');
      expect(s.ballVelocity.dx, greaterThan(0));
    });

    test('오른쪽 벽에 닿으면 왼쪽으로 튕긴다', () {
      final s = playing(
        ballPos: const Offset(390, 300),
        ballVelocity: const Offset(100, 0),
      );
      s.update(0.5);
      expect(s.ballPos.dx, 344);
      expect(s.ballVelocity.dx, lessThan(0));
    });

    test('위 벽에 닿으면 아래로 튕긴다', () {
      final s = playing(
        ballPos: const Offset(200, 10),
        ballVelocity: const Offset(0, -100),
      );
      s.update(0.2); // 벽돌(y 56~)까지 내려가지 않을 만큼만
      expect(s.ballPos.dy, 26, reason: '벽면 8 에서 되꺾여 18 만큼 더 간다');
      expect(s.ballVelocity.dy, greaterThan(0));
    });

    test('튕겨도 속도 크기는 유지된다', () {
      final s = playing(
        ballPos: const Offset(10, 300),
        ballVelocity: const Offset(-100, 60),
      );
      s.update(0.5);
      expect(s.ballVelocity.distance,
          closeTo(const Offset(-100, 60).distance, 0.001));
    });
  });
}

void paddleTests() {
  group('패들', () {
    test('경기장 밖으로는 나가지 않는다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      s.movePaddleTo(-100);
      expect(s.paddleX, s.paddleWidth / 2);
      s.movePaddleTo(9999);
      expect(s.paddleX, 400 - s.paddleWidth / 2);
    });

    test('패들에 맞으면 위로 튕긴다', () {
      final s = playing(
        ballPos: const Offset(200, 500),
        ballVelocity: const Offset(0, 300),
      );
      s.update(0.2);
      expect(s.ballVelocity.dy, lessThan(0));
      // 2026-09-03 : 패들 면에 붙여 세우지 않고 남은 거리만큼 더 올라간다
      expect(s.ballPos.dy, lessThan(s.paddleTop - s.ballRadius));
      expect(s.lives, BrickState.maxLives);
    });

    test('가운데에 맞으면 거의 수직으로 올라간다', () {
      final s = playing(
        ballPos: const Offset(200, 500),
        ballVelocity: const Offset(0, 300),
      );
      s.update(0.2);
      expect(s.ballVelocity.dx.abs(), lessThan(1));
    });

    test('가장자리에 맞으면 옆으로 크게 꺾인다', () {
      final s = playing(
        ballPos: const Offset(243, 500),
        ballVelocity: const Offset(0, 300),
      );
      s.update(0.2);
      expect(s.ballVelocity.dx, greaterThan(100));
      expect(s.ballVelocity.dy, lessThan(0));
    });

    test('튕겨도 속도 크기는 유지된다', () {
      final s = playing(
        ballPos: const Offset(230, 500),
        ballVelocity: const Offset(0, 300),
      );
      s.update(0.2);
      expect(s.ballVelocity.distance, closeTo(300, 0.001));
    });
  });
}

void paddleTunnelTests() {
  group('패들 통과 방지', () {
    test('빠르게 대각선으로 내려와도 패들을 뚫지 않는다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.ballPos = Offset(180, s.paddleTop - 20);
      s.ballVelocity = const Offset(400, 3000); // 한 프레임에 50px
      s.update(1 / 60);
      expect(s.lives, BrickState.maxLives);
      expect(s.ballVelocity.dy, lessThan(0));
    });

    test('넘어서는 순간의 x 로 판정한다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.ballPos = Offset(200, s.paddleTop - 20);
      s.ballVelocity = const Offset(6000, 1800); // 프레임 끝 x 는 패들 밖
      s.update(1 / 60);
      expect(s.lives, BrickState.maxLives);
      expect(s.ballVelocity.dy, lessThan(0));
    });

    test('패들과 이미 겹친 채 내려오면 튕긴다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.ballPos = Offset(200, s.paddleTop + 4);
      s.ballVelocity = const Offset(0, 200);
      s.update(1 / 60);
      expect(s.lives, BrickState.maxLives);
      expect(s.ballVelocity.dy, lessThan(0));
    });

    test('패들에서 완전히 벗어나면 여전히 놓친다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.ballPos = Offset(20, s.paddleTop - 10);
      s.ballVelocity = const Offset(0, 3000);
      for (var i = 0; i < 10 && s.lives == BrickState.maxLives; i++) {
        s.update(1 / 60);
      }
      expect(s.lives, BrickState.maxLives - 1);
    });
  });
}

void brickTests() {
  group('벽돌', () {
    test('스테이지 1 은 파랑(1회)만 3줄 × 7칸', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      expect(s.brickRows, 3);
      expect(s.brickCols, 7);
      expect(s.bricks.length, 21);
      expect(s.bricks.every((b) => b.hp == 1), isTrue);
    });

    test('내구도 1 짜리는 한 번에 사라진다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      final target = s.bricks.firstWhere((b) => b.row == s.brickRows - 1);
      final r = s.brickRect(target);

      s.ballPos = Offset(r.center.dx, r.bottom + 20);
      s.ballVelocity = const Offset(0, -300);
      s.update(0.1);

      expect(target.alive, isFalse);
      expect(s.score, 1);
      expect(s.ballVelocity.dy, greaterThan(0));
    });

    test('내구도가 여러 번이면 그만큼 맞아야 사라진다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      final target = s.bricks.first;
      target.hp = 3;
      final r = s.brickRect(target);

      for (var i = 0; i < 2; i++) {
        s.ballPos = Offset(r.center.dx, r.bottom + 20);
        s.ballVelocity = const Offset(0, -300);
        s.update(0.1);
      }
      expect(target.hp, 1);
      expect(target.alive, isTrue);

      s.ballPos = Offset(r.center.dx, r.bottom + 20);
      s.ballVelocity = const Offset(0, -300);
      s.update(0.1);
      expect(target.alive, isFalse);
    });

    test('옆에서 맞으면 좌우로 튕긴다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      final target = s.bricks.firstWhere((b) => b.row == 0 && b.col == 3);
      final r = s.brickRect(target);

      s.ballPos = Offset(r.left - 20, r.center.dy);
      s.ballVelocity = const Offset(300, 0);
      s.update(0.1);

      expect(target.alive, isFalse);
      expect(s.ballVelocity.dx, lessThan(0));
    });

    test('한 프레임에 한 개만 맞는다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      final r0 = s.brickRect(s.bricks.first);
      s.ballPos = r0.center;
      s.ballVelocity = const Offset(2000, 0);
      s.update(0.1);
      expect(s.score, 1);
    });

    test('깨진 벽돌은 다시 맞지 않는다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      final target = s.bricks.first;
      target.hp = 0;
      final r = s.brickRect(target);

      s.ballPos = Offset(r.center.dx, r.bottom + 20);
      s.ballVelocity = const Offset(0, -300);
      s.update(0.1);

      expect(s.score, 0);
    });
  });
}

void progressTests() {
  group('진행', () {
    test('처음에는 대기 상태이고 공이 패들 위에 얹혀 있다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      expect(s.status, GameStatus.ready);
      expect(s.ballVelocity, Offset.zero);
      expect(s.ballPos.dx, s.paddleX);
      expect(s.ballPos.dy, s.paddleTop - s.ballRadius);
      expect(s.stageIntro, isTrue);
    });

    test('대기 중에는 패들을 따라 공도 움직인다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.movePaddleTo(120);
      expect(s.ballPos.dx, 120);
    });

    test('대기 중에는 시간이 흘러도 공이 움직이지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      final before = s.ballPos;
      s.update(1);
      expect(s.ballPos, before);
    });

    test('발사하면 위로 날아가고 안내가 사라진다', () {
      final s = BrickState(fieldSize: const Size(400, 600), random: Random(1));
      s.launch();
      expect(s.status, GameStatus.playing);
      expect(s.ballVelocity.dy, lessThan(0));
      expect(s.stageIntro, isFalse);
    });

    test('발사 각도는 수직 기준 좌우 45도 안이다', () {
      for (var seed = 0; seed < 50; seed++) {
        final s = BrickState(fieldSize: const Size(400, 600), random: Random(seed));
        s.launch();
        final v = s.ballVelocity;
        final angle = atan2(v.dx.abs(), -v.dy); // 수직(위쪽)과 이루는 각
        expect(angle, lessThanOrEqualTo(BrickState.launchSpread + 0.0001));
        expect(v.distance, closeTo(s.ballSpeed, 0.001));
      }
    });

    test('공을 놓치면 목숨이 줄고 다시 대기 상태가 된다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.stageIntro = false;
      s.ballPos = Offset(20, s.paddleTop - 10);
      s.ballVelocity = const Offset(0, 3000);
      for (var i = 0; i < 10 && s.status == GameStatus.playing; i++) {
        s.update(1 / 60);
      }
      expect(s.lives, 2);
      expect(s.status, GameStatus.ready);
      expect(s.ballVelocity, Offset.zero);
      expect(s.stageIntro, isFalse); // 스테이지 안내는 다시 뜨지 않는다
    });

    test('목숨을 다 쓰면 게임오버', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      for (var life = 0; life < BrickState.maxLives; life++) {
        s.status = GameStatus.playing;
        s.ballPos = Offset(20, s.paddleTop - 10);
        s.ballVelocity = const Offset(0, 3000);
        for (var i = 0; i < 10 && s.status == GameStatus.playing; i++) {
          s.update(1 / 60);
        }
      }
      expect(s.lives, 0);
      expect(s.status, GameStatus.gameOver);
    });

    test('벽돌을 다 깨면 다음 스테이지로 넘어간다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      for (final b in s.bricks) {
        b.hp = 0;
      }
      s.ballVelocity = const Offset(0, -10);
      s.update(1 / 60);
      expect(s.stage, 2);
      expect(s.status, GameStatus.ready);
    });

    test('마지막 스테이지에서 다 깨면 CLEARED', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      s.loadStage(BrickState.stages.length);
      s.status = GameStatus.playing;
      for (final b in s.bricks) {
        b.hp = 0;
      }
      s.ballVelocity = const Offset(0, -10);
      s.update(1 / 60);
      expect(s.status, GameStatus.cleared);
    });

    test('restart 하면 목숨·점수·스테이지가 처음으로 돌아간다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      s.lives = 1;
      s.score = 10;
      s.bricks.first.hp = 0;

      s.restart();

      expect(s.lives, BrickState.maxLives);
      expect(s.score, 0);
      expect(s.stage, 1);
      expect(s.status, GameStatus.ready);
      expect(s.remainingBricks, s.bricks.length);
      expect(s.stageIntro, isTrue);
    });

    test('스테이지는 11개이고 11이 마지막이다', () {
      expect(BrickState.stages.length, 11);
      final s = BrickState(fieldSize: const Size(400, 600));
      expect(s.isLastStage, isFalse);
      s.loadStage(11);
      expect(s.isLastStage, isTrue);
    });
  });
}

// 끝난 뒤의 동작 — GAME OVER 와 CLEARED 를 같게 맞춘다 (2026-09-02)
void finishedTests() {
  group('끝난 뒤', () {
    test('게임오버와 클리어 모두 isFinished 가 참이다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.status = GameStatus.gameOver;
      expect(s.isFinished, isTrue);
      s.status = GameStatus.cleared;
      expect(s.isFinished, isTrue);
      s.status = GameStatus.ready;
      expect(s.isFinished, isFalse);
      s.status = GameStatus.playing;
      expect(s.isFinished, isFalse);
    });

    test('끝난 뒤에는 패들이 움직이지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      final before = s.paddleX;
      s.status = GameStatus.gameOver;
      s.movePaddleTo(50);
      expect(s.paddleX, before);

      s.status = GameStatus.cleared;
      s.movePaddleTo(350);
      expect(s.paddleX, before);
    });

    test('다시 시작하면 다시 움직인다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.status = GameStatus.gameOver;
      s.restart();
      s.movePaddleTo(150);
      expect(s.paddleX, 150);
    });
  });
}

// 스테이지 구성과 진행 (2026-09-02)
void stageTests() {
  group('스테이지', () {
    test('구성 — 1: 파랑3줄 / 2: 가운데 노랑 / 3: 가운데 빨강', () {
      expect(BrickState.stages[0].rowHp, [1, 1, 1]);
      expect(BrickState.stages[1].rowHp, [1, 2, 1]);
      expect(BrickState.stages[2].rowHp, [1, 3, 1]);
    });

    test('클리어 총점이 표와 맞는다 (내구도 합 × 7칸)', () {
      const expected = [21, 28, 35, 35, 42, 49, 56, 63, 70, 77, 77];
      for (var i = 0; i < BrickState.stages.length; i++) {
        final total =
            BrickState.stages[i].rowHp.fold<int>(0, (a, b) => a + b) * 7;
        expect(total, expected[i], reason: 'STAGE ${i + 1}');
      }
    });

    test('공 속도 단계 — 1~3 은 1, 4~10 은 2, 11 은 3', () {
      for (var i = 0; i < BrickState.stages.length; i++) {
        final level = BrickState.stages[i].speedLevel;
        final n = i + 1;
        expect(level, n <= 3 ? 1 : (n <= 10 ? 2 : 3), reason: 'STAGE $n');
      }
      // 2026-09-03 : 배수(%) 가 아니라 초당 픽셀 실제값으로 바꿨다
      expect(BrickState.speedTable, [250, 300, 390, 480, 570]);
    });

    test('단계표는 계속 빨라지기만 한다', () {
      for (var i = 1; i < BrickState.speedTable.length; i++) {
        expect(BrickState.speedTable[i],
            greaterThan(BrickState.speedTable[i - 1]));
      }
    });

    test('스테이지가 오르면 실제 발사 속도도 오른다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      expect(s.ballSpeed, 300);
      s.loadStage(4);
      expect(s.ballSpeed, 390);
      s.loadStage(11);
      expect(s.ballSpeed, 480);
    });

    test('스테이지가 넘어갈 때는 값만 바뀌고 깜빡이지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.loadStage(3); // 3 → 4 에서 기본 단계가 달라진다
      expect(s.speedMark, BrickState.speedMarks[1]);

      s.loadStage(4);
      expect(s.speedMark, BrickState.speedMarks[2], reason: '값은 바뀐다');
      expect(s.speedFlash, 0, reason: '깜빡임은 아이템으로 바뀐 경우에만');
      expect(s.speedBlinkOn, isTrue);
    });

    test('11 은 10 과 벽돌 구성이 같고 속도만 다르다', () {
      expect(BrickState.stages[10].rowHp, BrickState.stages[9].rowHp);
      expect(BrickState.stages[10].speedLevel,
          greaterThan(BrickState.stages[9].speedLevel));
    });

    test('스테이지 2 는 가운데 줄만 내구도 2', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.loadStage(2);
      expect(s.bricks.where((b) => b.row == 0).every((b) => b.hp == 1), isTrue);
      expect(s.bricks.where((b) => b.row == 1).every((b) => b.hp == 2), isTrue);
      expect(s.bricks.where((b) => b.row == 2).every((b) => b.hp == 1), isTrue);
    });

    test('다 깨면 다음 스테이지로 넘어가고 목숨·점수는 유지된다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      s.lives = 2;
      s.score = 7;

      s.debugClearStage();

      expect(s.stage, 2);
      expect(s.status, GameStatus.ready);
      expect(s.lives, 2);
      expect(s.score, 7);
      expect(s.remainingBricks, s.bricks.length);
      expect(s.stageIntro, isTrue);
    });

    test('마지막 스테이지를 깨면 CLEARED 에서 끝난다', () {
      final s = playing(ballPos: const Offset(200, 300), ballVelocity: Offset.zero);
      s.loadStage(BrickState.stages.length);
      s.debugClearStage();
      expect(s.status, GameStatus.cleared);
      expect(s.stage, BrickState.stages.length);
    });

    test('치트 — 스테이지 이동은 범위를 벗어나지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugGoToStage(99);
      expect(s.stage, BrickState.stages.length);
      s.debugGoToStage(0);
      expect(s.stage, 1);
    });

    test('치트 — 게임오버로 바로 간다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugGameOver();
      expect(s.status, GameStatus.gameOver);
      expect(s.isFinished, isTrue);
    });
  });
}

// 벽에 붙어 올라갈 때 벽돌을 뚫고 지나가던 문제 (2026-09-02)
void wallHugTests() {
  group('벽 붙어 상승', () {
    test('왼쪽 벽에 붙어 올라가다 아랫줄 벽돌에 맞으면 아래로 튕긴다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4); // 5줄짜리
      s.status = GameStatus.playing;

      final bottomLeft =
          s.bricks.firstWhere((b) => b.row == s.brickRows - 1 && b.col == 0);
      final r = s.brickRect(bottomLeft);

      // 공을 왼쪽 벽에 붙인 채(벽돌과 좌우로 이미 겹친 상태) 위로 올린다
      s.ballPos = Offset(s.ballRadius, r.bottom + 6);
      s.ballVelocity = const Offset(0, -300);

      s.update(1 / 60);

      expect(bottomLeft.alive, isFalse);
      expect(s.ballVelocity.dy, greaterThan(0), reason: '아래로 튕겨야 한다');
    });

    test('벽에 붙어 올라가도 한 줄을 통째로 뚫지 못한다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4);
      s.status = GameStatus.playing;

      final r = s.brickRect(
        s.bricks.firstWhere((b) => b.row == s.brickRows - 1 && b.col == 0),
      );
      s.ballPos = Offset(s.ballRadius, r.bottom + 6);
      s.ballVelocity = const Offset(0, -300);

      final before = s.remainingBricks;
      for (var i = 0; i < 20; i++) {
        s.update(1 / 60);
      }

      // 아래로 튕겨 나가므로 부서진 벽돌은 1개뿐이어야 한다
      expect(before - s.remainingBricks, lessThanOrEqualTo(1));
    });

    test('오른쪽 벽에서도 같다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4);
      s.status = GameStatus.playing;

      final last = s.bricks.firstWhere(
        (b) => b.row == s.brickRows - 1 && b.col == s.brickCols - 1,
      );
      final r = s.brickRect(last);
      s.ballPos = Offset(s.fieldSize.width - s.ballRadius, r.bottom + 6);
      s.ballVelocity = const Offset(0, -300);

      final before = s.remainingBricks;
      for (var i = 0; i < 20; i++) {
        s.update(1 / 60);
      }

      expect(before - s.remainingBricks, lessThanOrEqualTo(1));
      expect(s.ballVelocity.dy, greaterThan(0));
    });

    test('공은 언제나 경기장 안에 있다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(10);
      s.status = GameStatus.playing;
      s.ballPos = Offset(s.ballRadius, 300);
      s.ballVelocity = const Offset(-400, -400);

      for (var i = 0; i < 200; i++) {
        s.update(1 / 60);
        expect(s.ballPos.dx, greaterThanOrEqualTo(s.ballRadius - 0.001));
        expect(s.ballPos.dx,
            lessThanOrEqualTo(s.fieldSize.width - s.ballRadius + 0.001));
      }
    });
  });
}

// 벽돌 사이 틈·빈 열에서도 같은 문제가 없는지 (2026-09-02 점검)
void gapTests() {
  group('벽돌 사이', () {
    test('틈은 공 지름보다 좁다 — 공이 낄 수 없다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      expect(s.brickGap, lessThan(s.ballRadius * 2));
    });

    test('두 벽돌 사이 틈 가운데로 올라가면 아래로 튕기고 1개만 부서진다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4); // 5줄
      s.status = GameStatus.playing;

      final left = s.bricks
          .firstWhere((b) => b.row == s.brickRows - 1 && b.col == 2);
      final r = s.brickRect(left);
      final gapCenter = r.right + s.brickGap / 2;

      s.ballPos = Offset(gapCenter, r.bottom + 6);
      s.ballVelocity = const Offset(0, -300);

      final before = s.remainingBricks;
      for (var i = 0; i < 20; i++) {
        s.update(1 / 60);
      }

      expect(before - s.remainingBricks, lessThanOrEqualTo(1));
      expect(s.ballVelocity.dy, greaterThan(0), reason: '아래로 튕겨야 한다');
    });

    test('부서져 생긴 빈 열을 따라 올라가도 옆줄을 뚫지 않는다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4);
      s.status = GameStatus.playing;

      // 3번 열을 통째로 비워 통로를 만든다
      for (final b in s.bricks.where((b) => b.col == 3)) {
        b.hp = 0;
      }
      final col3 = s.brickRect(s.bricks.firstWhere((b) => b.col == 3));

      // 통로를 따라 살짝 비스듬히 올라간다
      s.ballPos = Offset(col3.center.dx, s.paddleTop - 40);
      s.ballVelocity = const Offset(60, -300);

      final before = s.remainingBricks;
      for (var i = 0; i < 60; i++) {
        s.update(1 / 60);
      }

      // 통로 옆을 스치며 몇 개는 부술 수 있지만 한 줄(7개)이 통째로 사라지면 안 된다
      expect(before - s.remainingBricks, lessThan(5));
    });

    test('벽돌 밭 한가운데를 지나도 한 프레임에 하나씩만 부순다', () {
      final s = playing(ballPos: Offset.zero, ballVelocity: Offset.zero);
      s.loadStage(4);
      s.status = GameStatus.playing;

      final r = s.brickRect(s.bricks.firstWhere((b) => b.row == 2 && b.col == 3));
      s.ballPos = r.center;
      s.ballVelocity = const Offset(0, -300);

      final before = s.remainingBricks;
      s.update(1 / 60);
      expect(before - s.remainingBricks, 1);
    });
  });
}

// 아이템 시험용 샘플 스테이지 (2026-09-02)
void sampleStageTests() {
  group('샘플 스테이지', () {
    test('파랑 5줄(35칸)이고 샘플로 표시된다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      expect(s.isSampleStage, isTrue);
      expect(s.brickRows, 5);
      expect(s.bricks.length, 35);
      expect(s.bricks.every((b) => b.hp == 1), isTrue);
      expect(s.status, GameStatus.ready);
    });

    test('무적공만 빠지고 나머지가 2개씩 들어간다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();

      for (final t in BrickState.sampleExcluded) {
        expect(s.bricks.any((b) => b.item == t), isFalse, reason: t.name);
      }
      for (final t in ItemType.values) {
        if (BrickState.sampleExcluded.contains(t)) continue;
        expect(s.bricks.where((b) => b.item == t).length,
            BrickState.sampleItemsEach,
            reason: t.name);
      }
    });

    test('샘플의 시작 속도는 단계 1 이다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      expect(s.speedStage, 1);
      expect(s.ballSpeed, 300);
    });

    test('다 깨면 CLEARED 로 끝난다 — 실제 스테이지로 넘어가지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      s.debugClearStage();
      expect(s.status, GameStatus.cleared);
      expect(s.isSampleStage, isTrue);
    });

    test('클리어 후 다시 시작하면 샘플이 다시 깔린다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      s.debugClearStage();
      s.restart();
      expect(s.isSampleStage, isTrue);
      expect(s.status, GameStatus.ready);
      expect(s.remainingBricks, 35);
      expect(s.lives, BrickState.maxLives);
      expect(s.score, 0);
    });

    test('게임오버 후 다시 시작해도 샘플이다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      s.debugGameOver();
      s.restart();
      expect(s.isSampleStage, isTrue);
      expect(s.lives, BrickState.maxLives);
    });

    test('실제 스테이지에서 다시 시작하면 스테이지 1 이다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugGoToStage(5);
      s.restart();
      expect(s.stage, 1);
      expect(s.isSampleStage, isFalse);
    });

    test('실제 스테이지 번호와 섞이지 않는다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      s.debugLoadSampleStage();
      expect(s.stage, BrickState.sampleStage);
      s.debugGoToStage(1);
      expect(s.isSampleStage, isFalse);
    });
  });
}

// 공 목록 전환 — 멀티볼 준비 (2026-09-02)
void multiBallTests() {
  group('멀티볼', () {
    test('평소에는 공이 1개다', () {
      final s = BrickState(fieldSize: const Size(400, 600));
      expect(s.balls.length, 1);
      expect(s.ballPos, s.balls.first.pos);
    });

    test('나누면 개수가 늘고 속도 크기는 그대로다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(0, -300),
      );
      s.splitBalls(3);
      expect(s.balls.length, 3);
      for (final b in s.balls) {
        expect(b.velocity.distance, closeTo(300, 0.001));
      }
      // 서로 다른 방향으로 퍼진다
      expect(s.balls[1].velocity.dx, isNot(closeTo(s.balls[0].velocity.dx, 1)));
    });

    // 2026-09-03 : 예전에는 +15도 · **-30도** 로 한쪽에 치우쳐 퍼졌다
    test('좌우로 같은 각도만큼 퍼진다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(0, -300),
      );
      s.splitBalls(3);

      // 위로 똑바로 가던 공이므로 좌우 x 속도가 부호만 다르고 크기는 같아야 한다
      final xs = s.balls.map((b) => b.velocity.dx).toList()..sort();
      expect(xs[1], closeTo(0, 0.001), reason: '가운데 공은 그대로');
      expect(xs[0], closeTo(-xs[2], 0.001), reason: '좌우 대칭');
    });

    test('공 하나가 빠져도 목숨은 줄지 않는다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(0, -300),
      );
      s.splitBalls(3);
      // 한 개만 바닥 아래로 보낸다
      s.balls[1].pos = Offset(30, s.fieldSize.height - 4);
      s.balls[1].velocity = const Offset(0, 3000);

      for (var i = 0; i < 5 && s.balls.length == 3; i++) {
        s.update(1 / 60);
      }

      expect(s.balls.length, 2);
      expect(s.lives, BrickState.maxLives);
      expect(s.status, GameStatus.playing);
    });

    test('공이 전부 빠져야 목숨이 준다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(0, -300),
      );
      s.splitBalls(3);
      for (final b in s.balls) {
        b.pos = Offset(b.pos.dx, s.fieldSize.height - 4);
        b.velocity = const Offset(0, 3000);
      }

      for (var i = 0; i < 5 && s.status == GameStatus.playing; i++) {
        s.update(1 / 60);
      }

      expect(s.lives, BrickState.maxLives - 1);
      expect(s.status, GameStatus.ready);
      expect(s.balls.length, 1, reason: '다시 시작하면 공은 1개로 돌아온다');
    });

    test('다시 대기 상태가 되면 공이 1개로 정리된다', () {
      final s = playing(
        ballPos: const Offset(200, 300),
        ballVelocity: const Offset(0, -300),
      );
      s.splitBalls(3);
      s.restart();
      expect(s.balls.length, 1);
    });
  });

  // 2026-09-03 : 부딪힌 프레임만 덜 가서 「멈칫 → 가속」으로 보이던 문제.
  //   부딪힌 면까지 간 거리 + 되꺾여 간 거리 = 원래 한 프레임 거리 여야 한다.
  group('부딪힌 프레임도 간 거리는 같다', () {
    const dt = 1 / 60;

    test('왼쪽 벽 — 넘어간 만큼 되꺾인다', () {
      final s = BrickState(
        fieldSize: const Size(400, 600),
        ballPos: const Offset(11, 300),
        ballVelocity: const Offset(-300, 0),
        status: GameStatus.playing,
      );
      s.status = GameStatus.playing;

      final r0 = s.ballRadius;
      final from = s.ballPos.dx;
      s.update(dt); // 5px 진행 → 벽을 3px 넘어감
      final path = (from - r0) + (s.ballPos.dx - r0);
      expect(path, closeTo(s.ballSpeed * dt, 0.001));
      expect(s.ballVelocity.dx, greaterThan(0));
    });

    test('벽돌 — 파고든 만큼 되꺾인다', () {
      final s = BrickState(fieldSize: const Size(400, 600), stage: 1);
      s.status = GameStatus.playing;

      final target = s.bricks.firstWhere((b) => b.col == 3 && b.row == 2);
      final r = s.brickRect(target);
      final face = r.bottom + s.ballRadius;
      s.ballPos = Offset(r.center.dx, face + 3); // 5px 중 3px 만에 닿는다
      s.ballVelocity = Offset(0, -s.ballSpeed);

      final from = s.ballPos.dy;
      s.update(dt);
      final path = (from - face) + (s.ballPos.dy - face);
      expect(path, closeTo(s.ballSpeed * dt, 0.001));
      expect(s.ballVelocity.dy, greaterThan(0), reason: '아래로 튕긴다');
    });

    test('패들 — 남은 거리를 새 방향으로 마저 간다', () {
      final s = BrickState(fieldSize: const Size(400, 600), stage: 1);
      s.status = GameStatus.playing;

      final face = s.paddleTop - s.ballRadius;
      s.paddleX = 200;
      s.ballPos = Offset(200, face - 3); // 5px 중 3px 만에 닿는다
      s.ballVelocity = Offset(0, s.ballSpeed);

      final from = s.ballPos;
      s.update(dt);
      final path = (face - from.dy) + (s.ballPos - Offset(200, face)).distance;
      expect(path, closeTo(s.ballSpeed * dt, 0.5));
      expect(s.ballVelocity.dy, lessThan(0), reason: '위로 튕긴다');
    });

    test('속력은 어디에 맞아도 그대로다', () {
      final s = BrickState(fieldSize: const Size(400, 600), stage: 1);
      s.status = GameStatus.playing;
      s.ballPos = const Offset(30, 300);
      s.ballVelocity = Offset(-s.ballSpeed * 0.6, -s.ballSpeed * 0.8);

      for (var i = 0; i < 120; i++) {
        if (s.status != GameStatus.playing) break;
        s.update(dt);
        for (final b in s.balls) {
          expect(b.velocity.distance, closeTo(s.ballSpeed, 0.001));
        }
      }
    });
  });
}
