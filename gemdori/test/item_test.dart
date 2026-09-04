// ═══════════════════════════════════════════════════════════════════
//  item_test.dart — 아이템 규칙 테스트
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 아이템의 획득·상쇄·지속·초기화 규칙 확인
//  제외 사항 : 화면 표시
//
//  주요 로직 : 반대 아이템은 서로 지운다(상쇄). 같은 아이템은 시간형만 리셋.
//    이 두 가지가 어긋나면 효과가 겹쳐 쌓이거나 영영 안 풀린다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/games/brick/brick_painter.dart';
import 'package:gemdori/games/brick/brick_state.dart';
import 'package:gemdori/games/brick/item.dart';

BrickState make({int stage = 1}) => BrickState(
      fieldSize: const Size(400, 600),
      random: Random(7),
      stage: stage,
    );

void main() {
  paddleClampTests();
  multiBallRefillTests();
  brickHpColorTests();
  group('아이템 정의', () {
    test('도움 4종 · 방해 6종 (생성 3색 포함)', () {
      final help = ItemType.values.where((t) => t.isHelp).length;
      final harm = ItemType.values.where((t) => !t.isHelp).length;
      expect(help, 4);
      expect(harm, 6);
      expect(ItemType.values.where((t) => t.isBrickSpawn).length, 3);
    });

    test('반대 짝이 서로를 가리킨다', () {
      expect(ItemType.paddleGrow.opposite, ItemType.paddleShrink);
      expect(ItemType.paddleShrink.opposite, ItemType.paddleGrow);
      expect(ItemType.slowBall.opposite, ItemType.fastBall);
      expect(ItemType.fastBall.opposite, ItemType.slowBall);
      expect(ItemType.multiBall.opposite, isNull);
    });

    test('벽돌 생성 3종만 즉발형', () {
      final instant =
          ItemType.values.where((t) => t.duration == ItemDuration.instant);
      expect(instant.map((t) => t.spawnHp), [1, 2, 3]);
      expect(ItemType.brickSpawnHp1.duration, ItemDuration.instant);
      expect(ItemType.paddleGrow.duration, ItemDuration.untilLost);
      expect(ItemType.multiBall.duration, ItemDuration.untilLost);
      expect(ItemType.reverse.duration, ItemDuration.timed);
    });

    test('방해 아이템이 더 느리게 떨어진다', () {
      final help = FallingItem(type: ItemType.paddleGrow, pos: Offset.zero);
      final harm = FallingItem(type: ItemType.paddleShrink, pos: Offset.zero);
      expect(harm.speed, lessThan(help.speed));
    });
  });

  group('패들 크기', () {
    test('확대는 2배, 축소는 절반', () {
      final s = make();
      final base = s.basePaddleWidth;
      s.applyItem(ItemType.paddleGrow);
      expect(s.paddleWidth, base * 2);

      s.clearEffects();
      s.applyItem(ItemType.paddleShrink);
      expect(s.paddleWidth, base / 2);
    });

    test('확대 상태에서 축소를 먹으면 원래대로 돌아가고 둘 다 사라진다', () {
      final s = make();
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.paddleShrink);
      expect(s.paddleWidth, s.basePaddleWidth);
      expect(s.effects, isEmpty);
    });

    test('확대를 두 번 먹어도 3배가 되지 않는다', () {
      final s = make();
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.paddleGrow);
      expect(s.paddleWidth, s.basePaddleWidth * 2);
    });
  });

  // 2026-09-03 규칙 변경 — 속도는 「스테이지 기준 ±1」이 아니라
  // 단계표 안에서 한 칸씩 누적으로 움직인다.
  group('공 속도', () {
    test('먹을 때마다 한 칸씩 움직인다', () {
      final s = make(stage: 1); // 단계 1 = 300
      expect(s.ballSpeed, 300);

      s.applyItem(ItemType.fastBall);
      expect(s.ballSpeed, 390);

      s.applyItem(ItemType.fastBall);
      expect(s.ballSpeed, 480, reason: '두 번 먹으면 두 칸 올라간다');

      s.applyItem(ItemType.slowBall);
      expect(s.ballSpeed, 390, reason: '반대쪽은 상쇄가 아니라 한 칸 되돌리기');
    });

    test('표 밖으로는 안 나간다 — 끝단에서는 시간만 다시 찬다', () {
      final s = make(stage: 11); // 단계 5 = 670
      s.applyItem(ItemType.fastBall);
      expect(s.ballSpeed, 780, reason: '최고 단계');

      s.applyItem(ItemType.fastBall);
      expect(s.ballSpeed, 780, reason: '더 올라가지 않는다');
      expect(s.speedLeft, ItemType.fastBall.seconds, reason: '시간은 리셋된다');
    });

    test('속도는 상단 효과 목록에 남지 않는다 — 따로 표시하므로', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.fastBall);
      expect(s.effects, isEmpty);
      expect(s.speedMark, BrickState.speedMarks[2]);
    });

    test('시간이 다 되면 몇 칸을 움직였든 한 번에 기본으로 돌아온다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.fastBall);
      s.applyItem(ItemType.fastBall);
      expect(s.speedStage, 3);

      for (var i = 0; i < 11 * 60; i++) {
        s.update(1 / 60); // 11초 (지속 10초)
      }
      expect(s.speedStage, s.baseSpeedStage);
      expect(s.ballSpeed, 300);
    });

    test('아이템으로 바뀌면 두 번 깜빡인다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.fastBall);
      expect(s.speedFlash, BrickState.speedBlinkPeriod * 2, reason: '두 주기');

      // 켜짐 → 꺼짐이 두 번 오간다
      var toggles = 0;
      var prev = s.speedBlinkOn;
      for (var i = 0; i < 60; i++) {
        s.update(1 / 60);
        if (s.speedBlinkOn != prev) toggles++;
        prev = s.speedBlinkOn;
      }
      expect(toggles, greaterThanOrEqualTo(3));
      expect(s.speedFlash, 0, reason: '1초면 끝난다');
    });

    test('끝단이라 단계가 안 바뀌면 깜빡이지 않는다', () {
      final s = make(stage: 11); // 단계 5
      s.applyItem(ItemType.fastBall); // 6 으로
      s.speedFlash = 0;
      s.applyItem(ItemType.fastBall); // 더 못 올라감
      expect(s.speedFlash, 0);
    });

    test('풀리기 2초 전부터 깜빡인다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.fastBall); // 10초
      expect(s.speedExpiring, isFalse);

      for (var i = 0; i < 9 * 60; i++) {
        s.update(1 / 60); // 9초 경과 — 남은 1초
      }
      expect(s.speedExpiring, isTrue);

      // 남은 시간이 줄면서 켜짐/꺼짐이 번갈아 나온다
      final seen = <bool>{};
      for (var i = 0; i < 60; i++) {
        s.update(1 / 60);
        if (s.speedLeft > 0) seen.add(s.speedBlinkOn);
      }
      expect(seen, containsAll([true, false]));
    });

    test('효과가 끝나면 깜빡임도 멈춘다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.fastBall);
      for (var i = 0; i < 11 * 60; i++) {
        s.update(1 / 60);
      }
      expect(s.speedExpiring, isFalse);
      expect(s.speedBlinkOn, isTrue);
    });

    test('날아가던 공의 속력도 새 단계에 맞춰진다 — 방향은 그대로', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.ballVelocity = const Offset(0, -300);

      s.applyItem(ItemType.fastBall);
      expect(s.ballVelocity.distance, closeTo(390, 0.001));
      expect(s.ballVelocity.dx, closeTo(0, 0.001));
      expect(s.ballVelocity.dy, lessThan(0), reason: '위로 가던 방향 유지');
    });
  });

  // 2026-09-03 : 샘플에서 확인한 뒤 실제 스테이지까지 넓혔다
  group('먹은 아이템 반짝 표시', () {
    // 2026-09-03 규칙 변경 — 예전에는 시간형(무적공·반전·속도)을 뺐다.
    //   이 표시는 「무엇이 걸렸는가」가 아니라 「무엇을 먹었는가」라 예외를 두지 않는다.
    test('8종 전부 띄운다', () {
      for (final t in ItemType.values) {
        final s = make(stage: 1);
        s.applyItem(t);
        expect(s.flashItem, t, reason: '$t 를 먹었는데 안 뜬다');
        expect(s.flashLeft, BrickState.itemFlashSeconds);
      }
    });

    test('나중에 먹은 것으로 바뀐다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.multiBall);
      s.applyItem(ItemType.reverse);
      expect(s.flashItem, ItemType.reverse);
    });

    test('끝단이라 속도 단계가 안 바뀌어도 띄운다', () {
      // 예전에 신호가 통째로 비던 자리 — 단계가 그대로면 SPEED 깜빡임도 없었다
      final s = make(stage: 1);
      for (var i = 0; i < 5; i++) {
        s.applyItem(ItemType.fastBall);
      }
      final top = s.speedStage;
      s.flashItem = null;
      s.applyItem(ItemType.fastBall);
      expect(s.speedStage, top, reason: '끝단이라 단계는 그대로');
      expect(s.flashItem, ItemType.fastBall, reason: '그래도 먹은 것은 알려야 한다');
    });

    test('실제 스테이지에서도 뜬다', () {
      final s = make(stage: 5);
      expect(s.isSampleStage, isFalse);
      s.applyItem(ItemType.paddleGrow);
      expect(s.flashItem, ItemType.paddleGrow);
    });

    test('빠르게 나타나고 천천히 사라진다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.multiBall);
      expect(s.itemFlashOpacity, 0, reason: '먹은 순간은 아직 투명');

      // 0.1초 — 나타나는 중(0.2초)이라 절반쯤
      for (var i = 0; i < 6; i++) {
        s.update(1 / 60);
      }
      expect(s.itemFlashOpacity, closeTo(0.5, 0.1));

      // 0.2초 — 완전히 진해진다
      for (var i = 0; i < 6; i++) {
        s.update(1 / 60);
      }
      expect(s.itemFlashOpacity, closeTo(1, 0.1));

      // 그 뒤로는 천천히 옅어지기만 한다
      var prev = s.itemFlashOpacity;
      for (var i = 0; i < 60; i++) {
        s.update(1 / 60);
        expect(s.itemFlashOpacity, lessThanOrEqualTo(prev + 0.001));
        prev = s.itemFlashOpacity;
      }
      expect(prev, lessThan(0.7), reason: '사라지는 쪽이 훨씬 느리다');
    });

    test('2초가 지나면 사라진다', () {
      final s = make(stage: 1);
      s.status = GameStatus.playing;
      s.applyItem(ItemType.brickSpawnHp1);
      expect(s.flashItem, ItemType.brickSpawnHp1);

      for (var i = 0; i < 3 * 60; i++) {
        s.update(1 / 60);
      }
      expect(s.flashItem, isNull);
      expect(s.flashLeft, 0);
    });
  });

  group('지속 · 초기화', () {
    test('시간형은 시간이 지나면 풀린다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.applyItem(ItemType.reverse);
      expect(s.hasEffect(ItemType.reverse), isTrue);

      for (var i = 0; i < 5 * 60; i++) {
        s.update(1 / 60); // 5초
      }
      expect(s.hasEffect(ItemType.reverse), isFalse);
    });

    test('같은 시간형을 또 먹으면 시간이 다시 찬다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.applyItem(ItemType.reverse);
      for (var i = 0; i < 3 * 60; i++) {
        s.update(1 / 60); // 3초 경과 (남은 1초)
      }
      s.applyItem(ItemType.reverse); // 리셋
      for (var i = 0; i < 2 * 60; i++) {
        s.update(1 / 60); // 2초 더
      }
      expect(s.hasEffect(ItemType.reverse), isTrue, reason: '리셋됐으면 아직 남아 있다');
    });

    test('무기한형은 시간이 지나도 유지된다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.applyItem(ItemType.paddleGrow);
      for (var i = 0; i < 30 * 60; i++) {
        s.update(1 / 60); // 30초
      }
      expect(s.hasEffect(ItemType.paddleGrow), isTrue);
    });

    test('스테이지가 바뀌면 효과가 전부 사라진다', () {
      final s = make();
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.reverse);
      s.loadStage(2);
      expect(s.effects, isEmpty);
      expect(s.fallingItems, isEmpty);
    });

    test('공을 놓치면 효과가 전부 사라진다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.fastBall);

      s.ballPos = Offset(20, s.paddleTop - 10);
      s.ballVelocity = const Offset(0, 3000);
      for (var i = 0; i < 10 && s.status == GameStatus.playing; i++) {
        s.update(1 / 60);
      }
      expect(s.effects, isEmpty);
    });
  });

  group('좌우 반전', () {
    test('손을 오른쪽으로 옮기면 패들은 왼쪽으로 간다', () {
      final s = make();
      s.movePaddleTo(200); // 기준 위치
      s.applyItem(ItemType.reverse);
      s.movePaddleTo(200); // 반전 시작 기준점

      s.movePaddleTo(250); // 오른쪽으로 50

      expect(s.paddleX, 150); // 패들은 왼쪽으로 50
    });

    test('효과가 걸리는 순간에는 패들이 움직이지 않는다', () {
      final s = make();
      s.movePaddleTo(120);
      final before = s.paddleX;
      s.applyItem(ItemType.reverse);
      s.movePaddleTo(120); // 손을 안 움직이면 그대로
      expect(s.paddleX, before, reason: '순간 이동하면 안 된다');
    });

    test('반전이 풀리면 다시 정상으로 따라간다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.movePaddleTo(200);
      s.applyItem(ItemType.reverse);
      for (var i = 0; i < 5 * 60; i++) {
        s.update(1 / 60);
      }
      expect(s.hasEffect(ItemType.reverse), isFalse);
      s.movePaddleTo(150);
      expect(s.paddleX, 150);
    });
  });

  group('벽돌 부활', () {
    // 2026-09-04 — 부활한 벽돌은 빈 벽돌이어야 한다.
    //   부활 아이템이 든 벽돌을 깨서 부활시켰더니 같은 아이템이 또 나왔다.
    test('새로 생긴 벽돌에는 아이템이 없다', () {
      final s = make(stage: 9); // 아이템이 많이 심기는 스테이지
      s.status = GameStatus.playing;
      final row = s.brickRows - 1;
      for (final b in s.bricks.where((b) => b.row == row)) {
        b.hp = 0;
      }
      s.applyItem(ItemType.brickSpawnHp1);

      final made = s.bricks.where((b) => b.row == row).toList();
      expect(made.every((b) => b.alive), isTrue, reason: '새로 생겼다');
      expect(made.every((b) => b.item == null), isTrue,
          reason: '아이템은 딸려 오지 않는다');
    });

    test('깨진 줄 중 가장 아래 줄에 새로 생긴다', () {
      final s = make();
      for (final b in s.bricks.where((b) => b.row == s.brickRows - 1)) {
        b.hp = 0;
      }
      expect(s.remainingBricks, s.bricks.length - s.brickCols);

      s.applyItem(ItemType.brickSpawnHp1);

      expect(s.remainingBricks, s.bricks.length);
      expect(s.effects, isEmpty, reason: '즉발형이라 효과로 남지 않는다');
    });

    // 2026-09-04 — 색이 곧 생기는 벽돌 색이다 (RE 가 아니라 NEW)
    test('먹은 아이템 색으로 생긴다 — 원래 그 줄 색이 아니다', () {
      final s = make(stage: 3); // 줄 구성 1 3 1 — 가운데가 빨강
      final row = 1;
      final was = s.bricks.firstWhere((b) => b.row == row).hp;
      expect(was, 3, reason: '원래는 빨강 줄');
      for (final b in s.bricks.where((b) => b.row == row)) {
        b.hp = 0;
      }
      s.applyItem(ItemType.brickSpawnHp1);
      expect(s.bricks.where((b) => b.row == row).every((b) => b.hp == 1), isTrue,
          reason: '파랑 아이템을 먹었으니 파란 줄로 생긴다');
    });

    test('살아 있는 벽돌은 건드리지 않는다', () {
      final s = make(stage: 3);
      final row = 1;
      final line = s.bricks.where((b) => b.row == row).toList();
      for (final b in line.take(3)) {
        b.hp = 0;
      }
      s.applyItem(ItemType.brickSpawnHp2);

      expect(line.take(3).every((b) => b.hp == 2), isTrue, reason: '빈 자리만 노랑');
      expect(line.skip(3).every((b) => b.hp == 3), isTrue,
          reason: '살아 있던 빨강은 그대로');
    });

    test('스테이지별로 나올 수 있는 색이 다르다', () {
      expect(BrickState.spawnColorsFor(1), [ItemType.brickSpawnHp1]);
      expect(BrickState.spawnColorsFor(5), [ItemType.brickSpawnHp1]);
      expect(BrickState.spawnColorsFor(6).length, 2);
      expect(BrickState.spawnColorsFor(8).length, 2);
      expect(BrickState.spawnColorsFor(9).length, 3);
      expect(BrickState.spawnColorsFor(11).length, 3);
    });

    test('심을 때 스테이지가 허용하지 않는 색은 안 나온다', () {
      for (final stage in [1, 5, 7, 11]) {
        final s = make(stage: stage);
        final allowed = BrickState.spawnColorsFor(stage);
        final planted = s.bricks
            .where((b) => b.item != null && b.item!.isBrickSpawn)
            .map((b) => b.item!);
        for (final t in planted) {
          expect(allowed, contains(t), reason: 'STAGE $stage');
        }
      }
    });
  });

  group('아이템 배치', () {
    test('스테이지 표에 정한 개수만큼 벽돌에 심긴다', () {
      for (var n = 1; n <= BrickState.stages.length; n++) {
        final s = make(stage: n);
        final spec = BrickState.stages[n - 1];
        final help = s.bricks.where((b) => b.item?.isHelp == true).length;
        final harm = s.bricks.where((b) => b.item?.isHelp == false).length;
        expect(help, spec.helpItems, reason: 'STAGE $n 도움');
        expect(harm, spec.harmItems, reason: 'STAGE $n 방해');
      }
    });

    test('벽돌이 완전히 깨질 때만 떨어진다', () {
      final s = make(stage: 3); // 빨강(3회) 줄이 있는 스테이지
      s.status = GameStatus.playing;
      final target = s.bricks.firstWhere((b) => b.item != null && b.hp > 1);
      final r = s.brickRect(target);

      final hp = target.hp; // 루프 도중 줄어드므로 미리 잡아 둔다
      for (var hit = 0; hit < hp - 1; hit++) {
        s.ballPos = Offset(r.center.dx, r.bottom + 6);
        s.ballVelocity = const Offset(0, -300);
        s.update(1 / 60);
        expect(s.fallingItems, isEmpty, reason: '아직 안 깨졌다');
      }

      s.ballPos = Offset(r.center.dx, r.bottom + 6);
      s.ballVelocity = const Offset(0, -300);
      s.update(1 / 60);
      expect(s.fallingItems.length, 1);
    });

    test('패들에 닿으면 효과가 걸리고 아이템은 사라진다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.fallingItems.add(
        FallingItem(type: ItemType.paddleGrow, pos: Offset(s.paddleX, s.paddleTop - 4)),
      );
      s.update(1 / 60);
      expect(s.hasEffect(ItemType.paddleGrow), isTrue);
      expect(s.fallingItems, isEmpty);
    });

    test('못 받으면 바닥에서 사라진다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.fallingItems.add(
        FallingItem(type: ItemType.paddleGrow, pos: const Offset(20, 400)),
      );
      for (var i = 0; i < 5 * 60 && s.fallingItems.isNotEmpty; i++) {
        s.update(1 / 60);
      }
      expect(s.fallingItems, isEmpty);
      expect(s.hasEffect(ItemType.paddleGrow), isFalse);
    });
  });

  group('무적공', () {
    test('반사하지 않고 지나가며 겹친 벽돌을 모두 부순다', () {
      final s = make(stage: 4); // 파랑 5줄
      s.status = GameStatus.playing;
      s.applyItem(ItemType.invincibleBall);

      final bottom = s.brickRect(
        s.bricks.firstWhere((b) => b.row == s.brickRows - 1 && b.col == 3),
      );
      s.ballPos = Offset(bottom.center.dx, bottom.bottom + 6);
      s.ballVelocity = const Offset(0, -300);

      final before = s.remainingBricks;
      for (var i = 0; i < 30; i++) {
        s.update(1 / 60);
      }

      expect(s.ballVelocity.dy, lessThan(0), reason: '벽돌에 튕기지 않는다');
      expect(before - s.remainingBricks, greaterThan(1));
    });

    // 무적 중에는 공이 빨강 계열 3색을 돌며 번쩍인다 (2026-09-03)
    test('무적이 아니면 색을 지정하지 않는다', () {
      expect(make(stage: 1).invincibleColorIndex, isNull);
    });

    test('주기마다 0 → 1 → 2 로 돌고 다시 0 으로', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.invincibleBall);
      final total = ItemType.invincibleBall.seconds;
      const p = BrickState.ballFlashPeriod;

      expect(s.invincibleColorIndex, 0);
      s.effects[ItemType.invincibleBall] = total - p * 1.5;
      expect(s.invincibleColorIndex, 1);
      s.effects[ItemType.invincibleBall] = total - p * 2.5;
      expect(s.invincibleColorIndex, 2);
      s.effects[ItemType.invincibleBall] = total - p * 3.5;
      expect(s.invincibleColorIndex, 0, reason: '세 색을 돌고 처음으로');
    });

    test('효과가 풀리면 색도 사라진다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.invincibleBall);
      s.clearEffects();
      expect(s.invincibleColorIndex, isNull);
    });

    // 모양 교대 — 색보다 두 배 느리게 (2026-09-04)
    test('링은 색보다 두 배 느리게 켜졌다 꺼진다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.invincibleBall);
      final total = ItemType.invincibleBall.seconds;
      const p = BrickState.ballFlashPeriod;

      expect(s.invincibleRingOn, isFalse, reason: '처음엔 그냥 원');
      s.effects[ItemType.invincibleBall] = total - p * 2.5;
      expect(s.invincibleRingOn, isTrue);
      s.effects[ItemType.invincibleBall] = total - p * 4.5;
      expect(s.invincibleRingOn, isFalse, reason: '다시 원으로');
    });

    test('무적이 아니면 링도 없다', () {
      expect(make(stage: 1).invincibleRingOn, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  상단 표시줄 — 버프만, 번호순 (2026-09-04)
  // ═══════════════════════════════════════════════════════════════
  group('상단 표시 대상', () {
    test('갈래가 8종 전부에 정해져 있다', () {
      final buff = ItemType.values.where((t) => t.cls == ItemClass.buff);
      final gear = ItemType.values.where((t) => t.cls == ItemClass.gear);
      final con = ItemType.values.where((t) => t.cls == ItemClass.consumable);
      expect(buff.length, 4, reason: '무적·감속·반전·증속');
      expect(ItemType.values.length, 10);
      expect(gear.length, 3, reason: '멀티공·패들 확대·축소');
      expect(con.length, 3, reason: '벽돌 생성 3색');
    });

    test('장비는 걸려 있어도 상단에 안 올라간다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.multiBall);
      s.applyItem(ItemType.paddleGrow);
      expect(s.hasEffect(ItemType.multiBall), isTrue, reason: '효과 자체는 걸려 있다');
      expect(s.hudEffects, isEmpty, reason: '화면이 이미 보여주므로 상단엔 없다');
    });

    test('버프만 올라간다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.multiBall);
      s.applyItem(ItemType.reverse);
      s.applyItem(ItemType.invincibleBall);
      expect(s.hudEffects, [ItemType.invincibleBall, ItemType.reverse],
          reason: '먹은 순서가 아니라 번호순으로 고정');
    });

    test('속도는 상단에 안 올라간다 — SPEED 표시가 대신한다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.fastBall);
      expect(s.hudEffects, isEmpty);
    });
  });

  // 만료 2초 전 예고 — 속도에만 있던 것을 버프 전체로 (2026-09-04)
  group('버프 만료 예고', () {
    test('2초보다 많이 남았으면 계속 켜져 있다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.invincibleBall); // 6초
      expect(s.effectBlinkOn(ItemType.invincibleBall), isTrue);
      s.effects[ItemType.invincibleBall] = 2.5;
      expect(s.effectBlinkOn(ItemType.invincibleBall), isTrue);
    });

    test('2초 안으로 들어오면 깜빡인다', () {
      final s = make(stage: 1);
      s.applyItem(ItemType.invincibleBall);
      const p = BrickState.speedBlinkPeriod;
      s.effects[ItemType.invincibleBall] = p * 0.8; // 주기 앞쪽 = 켜짐
      expect(s.effectBlinkOn(ItemType.invincibleBall), isTrue);
      s.effects[ItemType.invincibleBall] = p * 0.2; // 주기 뒤쪽 = 꺼짐
      expect(s.effectBlinkOn(ItemType.invincibleBall), isFalse);
    });

    test('안 걸린 효과는 깜빡임 대상이 아니다', () {
      expect(make(stage: 1).effectBlinkOn(ItemType.reverse), isTrue);
    });
  });
}

// 패들이 화면 밖으로 삐져나가던 문제 (2026-09-02)
void paddleClampTests() {
  group('패들 위치 가두기', () {
    test('오른쪽 끝에서 확대되면 화면 안으로 들어온다', () {
      final s = make();
      s.movePaddleTo(9999); // 오른쪽 끝
      final before = s.paddleX;

      s.applyItem(ItemType.paddleGrow);

      expect(s.paddleX, lessThan(before), reason: '넓어진 만큼 안으로 들어와야 한다');
      expect(s.paddleRect.right, lessThanOrEqualTo(s.fieldSize.width + 0.001));
      expect(s.paddleRect.left, greaterThanOrEqualTo(-0.001));
    });

    test('왼쪽 끝에서도 마찬가지', () {
      final s = make();
      s.movePaddleTo(-9999);
      s.applyItem(ItemType.paddleGrow);
      expect(s.paddleRect.left, greaterThanOrEqualTo(-0.001));
    });

    test('효과가 풀릴 때도 화면 안에 있다', () {
      final s = make();
      s.status = GameStatus.playing;
      s.movePaddleTo(9999);
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.paddleShrink); // 상쇄 → 원래 크기
      expect(s.paddleRect.right, lessThanOrEqualTo(s.fieldSize.width + 0.001));
    });

    test('좌우 반전 중에 화면 크기가 바뀌어도 패들이 뒤집히지 않는다', () {
      final s = make();
      s.applyItem(ItemType.reverse);
      s.movePaddleTo(100); // 반전이라 300 에 놓인다
      final placed = s.paddleX;

      s.resize(const Size(400, 600)); // 같은 크기로 다시 맞춰도

      expect(s.paddleX, placed, reason: 'resize 가 위치를 뒤집으면 안 된다');
    });
  });
}

// 멀티공 다시 먹기 (2026-09-02)
void multiBallRefillTests() {
  group('멀티공 재획득', () {
    BrickState playing() {
      final s = make();
      s.status = GameStatus.playing;
      s.ballPos = const Offset(200, 300);
      s.ballVelocity = const Offset(0, -300);
      return s;
    }

    test('패들 크기를 바꾼 뒤에 먹어도 공이 3개가 된다', () {
      final s = playing();
      s.applyItem(ItemType.paddleGrow);
      s.applyItem(ItemType.multiBall);
      expect(s.balls.length, 3);
    });

    test('공이 1개로 줄었을 때 다시 먹으면 3개로 돌아온다', () {
      final s = playing();
      s.applyItem(ItemType.multiBall);
      expect(s.balls.length, 3);

      s.balls.removeRange(1, 3); // 두 개를 잃은 상황
      expect(s.balls.length, 1);

      s.applyItem(ItemType.multiBall);
      expect(s.balls.length, 3);
    });

    test('공이 2개일 때 다시 먹으면 가장 높이 있는 공이 갈라진다', () {
      final s = playing();
      s.applyItem(ItemType.multiBall);
      s.balls.removeAt(2); // 2개 남김
      // 나뉜 직후에는 공 위치가 겹쳐 있으므로 떨어뜨려 놓는다
      s.balls[0].pos = const Offset(150, 200); // 더 높은 쪽
      s.balls[1].pos = const Offset(250, 400);

      final high = s.balls.reduce((a, b) => a.pos.dy <= b.pos.dy ? a : b);
      final speed = high.velocity.distance;
      final highPos = high.pos;

      s.applyItem(ItemType.multiBall);

      expect(s.balls.length, 3);
      final fromHigh = s.balls.where((b) => b.pos == highPos).toList();
      expect(fromHigh.length, 2, reason: '높은 공이 둘로 갈라진다');
      for (final b in fromHigh) {
        expect(b.velocity.distance, closeTo(speed, 0.001));
      }
      expect(fromHigh[0].velocity.dx, isNot(closeTo(fromHigh[1].velocity.dx, 1)));
    });

    test('이미 3개면 더 늘지 않는다', () {
      final s = playing();
      s.applyItem(ItemType.multiBall);
      s.applyItem(ItemType.multiBall);
      expect(s.balls.length, 3);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════
//  내구도와 색 (2026-09-04)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 로직 : **내구도가 값이고 색은 따라오는 표현**이다.
//    색을 바꿔도 내구도는 그대로여야 하고, 색 값은 한 곳에만 있어야 한다.
//    사람이 기억해서 지키는 대신 여기서 못박는다.
void brickHpColorTests() {
  group('내구도와 색', () {
    test('색 개수와 최대 내구도가 어긋나지 않는다', () {
      expect(kBrickColors.length, BrickState.maxBrickHp);
      for (var hp = 1; hp <= BrickState.maxBrickHp; hp++) {
        expect(kBrickColors[hp], isNotNull, reason: '내구도 $hp 의 색이 없다');
      }
    });

    test('생성 아이템은 내구도 1~최대까지 하나씩 있다', () {
      final hps = ItemType.values
          .where((t) => t.isBrickSpawn)
          .map((t) => t.spawnHp)
          .toList()
        ..sort();
      expect(hps, [for (var i = 1; i <= BrickState.maxBrickHp; i++) i]);
    });

    test('생성 아이템 색 = 그 내구도의 벽돌 색', () {
      for (final t in ItemType.values.where((t) => t.isBrickSpawn)) {
        expect(kItemColors[t], kBrickColors[t.spawnHp], reason: '$t');
      }
    });

    test('벽돌은 색을 따로 들고 있지 않다 — 내구도만 바꾸면 색도 따라온다', () {
      final s = make(stage: 3);
      final b = s.bricks.firstWhere((b) => b.hp == 3);
      expect(kBrickColors[b.hp], kBrickColors[3]);
      b.hp = 1;
      expect(kBrickColors[b.hp], kBrickColors[1], reason: '내구도만 바꿔도 색이 따라온다');
    });
  });
}
