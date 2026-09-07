// ═══════════════════════════════════════════════════════════════════
//  sound.dart — 효과음 재생
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : BrickState 가 남긴 사건(GameEvent)을 받아 소리를 낸다
//  제외 사항 : 게임 규칙 · 사건을 만드는 일 (전부 BrickState 가 한다)
//
//  상세 설명
//    상태(BrickState)는 소리를 재생하지 않는다. 무슨 일이 있었는지만 남기고,
//    가져가서 재생하는 것은 이쪽 몫이다. 그래서 화면 없이 도는 테스트가 깨지지 않는다.
//
//  주요 로직 : 소리마다 **볼륨을 따로 준다.**
//    벽 반사는 초당 여러 번 나므로 가장 작게, 벽돌 맞음은 빨강 벽돌에서
//    연달아 두 번 나므로 낮춘다. 원본 파일의 진폭 차이도 여기서 함께 고른다.
//
//  주요 로직 : **같은 소리는 최소 간격을 둔다.**
//    무적공이 한 프레임에 벽돌을 여러 개 부수면 같은 소리가 겹쳐 터진다.
//    간격 안에 다시 들어온 같은 소리는 버린다.
//
//  주요 로직 : 재생기(플레이어)를 미리 여러 개 만들어 돌려 쓴다.
//    하나로 돌리면 앞 소리가 끊기고, 매번 새로 만들면 소리가 늦게 난다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:audioplayers/audioplayers.dart';

import 'brick_state.dart';

/// 소리 한 종류의 설정
class _Sfx {
  const _Sfx(this.file, this.volume, {this.gapMs = 40});

  final String file;

  /// 0~1. 파일마다 원본 크기가 달라 여기서 맞춘다
  final double volume;

  /// 같은 소리를 다시 낼 수 있게 되기까지의 최소 간격(밀리초)
  final int gapMs;
}

/// 사건별 소리 — **한 곳에서만 정한다.**
///
/// 주요 로직 : 볼륨은 2026-09-04 에 파일을 실측해 정했다.
///   원본 최대 진폭이 벽 45% · 벽돌맞음 72% · 공놓침 36% 로 제각각이라,
///   파일을 다시 만들지 않고 여기서 균형을 맞춘다.
const Map<GameEventType, _Sfx> _table = {
  // 벽돌 깨짐 — 가장 중요한 소리라 크게
  GameEventType.brickBroken: _Sfx('audio/brick_break.wav', 0.80),

  // 벽돌 맞음 — 원본이 커서(72%) 낮춘다. 빨강 벽돌에서 연달아 두 번 난다
  GameEventType.brickHit: _Sfx('audio/brick_hit.wav', 0.55),

  // 패들 반사 — 음이 높아(1420Hz~) 귀에 잘 꽂히므로 낮게
  GameEventType.paddleHit: _Sfx('audio/paddle.wav', 0.45),

  // 벽 반사 — 초당 여러 번. **가장 작게**
  GameEventType.wallHit: _Sfx('audio/wall.wav', 0.22, gapMs: 60),

  // 공 놓침 — 원본이 조용해서(36%) 그대로
  GameEventType.ballLost: _Sfx('audio/ball_lost.wav', 0.90, gapMs: 300),

  GameEventType.itemHelp: _Sfx('audio/item_help.wav', 0.70, gapMs: 120),
  GameEventType.itemHarm: _Sfx('audio/item_harm.wav', 0.70, gapMs: 120),
  GameEventType.launch: _Sfx('audio/launch.wav', 0.50, gapMs: 150),
};

/// 벽돌에 맞았을 때(안 깨짐) 내구도별 재생 속도.
///
/// 주요 로직 : 단단한 벽돌일수록 **낮고 묵직하게** 들린다.
///   재생 속도를 낮추면 음도 같이 내려가므로 파일을 따로 만들지 않아도 된다.
///
///   ⚠️ 「깨짐」에는 적용하지 않는다 — 깨지는 순간은 **언제나 마지막 한 대**라
///   그 사건이 싣고 오는 내구도가 항상 1이다. 색 정보가 남아 있지 않다.
const Map<int, double> _hitRate = {1: 1.00, 2: 0.92, 3: 0.84};

class GameSound {
  GameSound({int players = 6})
      : _pool = List.generate(players, (_) => AudioPlayer()) {
    for (final p in _pool) {
      p.setReleaseMode(ReleaseMode.stop);
    }
  }

  final List<AudioPlayer> _pool;
  int _next = 0;

  /// 사건 종류별 마지막 재생 시각 — 겹침 방지용
  final Map<GameEventType, DateTime> _last = {};

  bool muted = false;

  /// 이번 프레임에 일어난 사건들을 소리로 낸다.
  void playAll(List<GameEvent> events) {
    if (muted) return;
    for (final e in events) {
      _play(e);
    }
  }

  void _play(GameEvent e) {
    final sfx = _table[e.type];
    if (sfx == null) return;

    final now = DateTime.now();
    final last = _last[e.type];
    if (last != null && now.difference(last).inMilliseconds < sfx.gapMs) {
      return; // 너무 붙어 있으면 버린다
    }
    _last[e.type] = now;

    final player = _pool[_next];
    _next = (_next + 1) % _pool.length;

    final rate = e.type == GameEventType.brickHit
        ? (_hitRate[e.hp] ?? 1.0)
        : 1.0;

    // 실패해도 게임은 계속되어야 한다 — 소리는 곁가지다.
    // (웹은 첫 조작 전에 재생이 막혀 있어 여기서 예외가 날 수 있다)
    player.setVolume(sfx.volume).catchError((_) {});
    player.setPlaybackRate(rate).catchError((_) {});
    player.play(AssetSource(sfx.file), volume: sfx.volume).catchError((_) {});
  }

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}
