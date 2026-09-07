// 개발자 패널 — 표시 판별과 사건 로그 규칙
//
// 주요 로직 : 화면 없이 도는 테스트다. 패널을 그려 보는 것이 아니라
//   「언제 뜨는가」와 「무엇을 남기는가」 두 규칙만 붙든다.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemdori/app/dev_mode.dart';
import 'package:gemdori/games/brick/brick_state.dart';
import 'package:gemdori/games/brick/dev_panel.dart';

void main() {
  group('DevPanel.fitsIn — 폭으로만 가른다', () {
    test('폰 세로 폭에서는 안 뜬다', () {
      expect(DevPanel.fitsIn(360), isFalse);
      expect(DevPanel.fitsIn(430), isFalse);
    });

    test('경계 — 경기장 가로 상한을 남길 수 있는 폭부터 뜬다', () {
      final edge = BrickState.maxFieldWidth + DevPanel.width + DevPanel.gap;
      expect(DevPanel.fitsIn(edge), isTrue);
      expect(DevPanel.fitsIn(edge - 1), isFalse);
    });

    test('노트북 폭이면 뜬다', () {
      expect(DevPanel.fitsIn(1366), isTrue);
    });

    test('패널이 떠도 경기장은 상한을 그대로 쓴다', () {
      // 패널을 뺀 나머지로도 상한 크기가 나와야 한다 — 게임이 줄면 안 된다
      final rest = 1366 - (DevPanel.width + DevPanel.gap);
      final size = BrickState.fitField(Size(rest, 900));
      expect(size.height, BrickState.maxFieldHeight);
    });
  });

  group('개발 모드 — 실서비스 전환', () {
    test('테스트는 릴리스 빌드가 아니므로 켜져 있다', () {
      expect(devMode, isTrue);
    });

    test('표시 판별에 devMode 가 들어간다 — 화면 쪽에 분기를 두지 않는다', () {
      // 릴리스 빌드에서는 devMode 가 false 라 폭과 무관하게 안 뜬다
      expect(DevPanel.visibleIn(1366), devMode);
      expect(DevPanel.visibleIn(360), isFalse); // 폭이 모자라면 개발 모드여도 안 뜸
    });

    test('패널이 안 뜨면 게임이 전체 폭을 그대로 쓴다', () {
      expect(DevPanel.gameWidth(360), 360); // 좁아서 안 뜨는 경우
      expect(
        DevPanel.gameWidth(1366),
        devMode ? 1366 - (DevPanel.width + DevPanel.gap) : 1366,
      );
    });
  });

  group('크기 단계 (치트)', () {
    test('큰 단계는 상한 그대로 — 평소 동작과 같다', () {
      expect(BrickState.presetHeight(FieldPreset.large),
          BrickState.maxFieldHeight);
    });

    test('단계마다 크기가 실제로 달라진다', () {
      Size sizeOf(FieldPreset p) => BrickState.fitField(
            const Size(2000, 2000),
            maxHeight: BrickState.presetHeight(p),
          );
      expect(sizeOf(FieldPreset.small).height, 360);
      expect(sizeOf(FieldPreset.medium).height, 440);
      expect(sizeOf(FieldPreset.large).height, 520);
      // 비율(2:3)은 단계와 무관하게 유지된다
      for (final p in FieldPreset.values) {
        final s = sizeOf(p);
        expect(s.width / s.height, closeTo(BrickState.fieldAspect, 1e-9));
      }
    });

    test('화면이 그보다 작으면 화면에 맞춘다 — 넘치지 않는다', () {
      final s = BrickState.fitField(
        const Size(200, 300),
        maxHeight: BrickState.presetHeight(FieldPreset.large),
      );
      expect(s.height, lessThanOrEqualTo(300));
      expect(s.width, lessThanOrEqualTo(200));
    });

    test('단계를 바꿔도 난이도 기준은 그대로 — 패들이 폭의 15%', () {
      for (final p in FieldPreset.values) {
        final size = BrickState.fitField(const Size(2000, 2000),
            maxHeight: BrickState.presetHeight(p));
        final st = BrickState(fieldSize: size);
        expect(st.basePaddleWidth / size.width, closeTo(0.15, 1e-9));
      }
    });
  });

  group('크기가 바뀌어도 난이도는 그대로', () {
    // 공 크기는 **고정이 아니라 폭에 비례한다** — 확인 결과 지금 값이 좋다는 판정
    // (2026-09-07). 고정으로 바꾸면 작은 화면에서 공만 커져 난이도가 흔들린다.
    test('공 반지름이 경기장 폭에서 차지하는 비율이 단계와 무관하다', () {
      double ratio(FieldPreset p) {
        final size = BrickState.fitField(const Size(2000, 2000),
            maxHeight: BrickState.presetHeight(p));
        return BrickState(fieldSize: size).ballRadius / size.width;
      }

      final base = ratio(FieldPreset.large);
      for (final p in FieldPreset.values) {
        expect(ratio(p), closeTo(base, 1e-9));
      }
    });
  });

  group('EventLog', () {
    test('같은 사건이 이어지면 한 줄로 합쳐 센다', () {
      final log = EventLog()
        ..add(const GameEvent(GameEventType.wallHit))
        ..add(const GameEvent(GameEventType.wallHit))
        ..add(const GameEvent(GameEventType.wallHit));
      expect(log.lines.length, 1);
      expect(log.lines.first.count, 3);
      expect(log.lines.first.toString(), 'wallHit ×3');
    });

    test('내구도가 다르면 다른 줄이다', () {
      final log = EventLog()
        ..add(const GameEvent(GameEventType.brickHit, hp: 1))
        ..add(const GameEvent(GameEventType.brickHit, hp: 2));
      expect(log.lines.length, 2);
      expect(log.lines.first.label, 'brickHit hp:2'); // 최근이 앞
    });

    test('용량을 넘으면 오래된 것부터 버린다', () {
      final log = EventLog(capacity: 3);
      for (final hp in [1, 2, 3, 1]) {
        log.add(GameEvent(GameEventType.brickBroken, hp: hp));
      }
      expect(log.lines.length, 3);
      expect(log.lines.last.label, 'brickBroken hp:2'); // hp:1 이 밀려 나갔다
    });

    test('최근 것이 맨 앞에 온다', () {
      final log = EventLog()
        ..add(const GameEvent(GameEventType.launch))
        ..add(const GameEvent(GameEventType.paddleHit));
      expect(log.lines.first.label, 'paddleHit');
    });
  });
}
