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
//  ⭐ 주요 로직 : **부딪히는 소리는 한 갈래로 묶고 두 소리를 번갈아 낸다** (2026-09-07 변경).
//    벽·패들·벽돌깨짐을 각각 다른 소리로 두었더니 산만했다.
//    시중의 벽돌깨기들이 그렇듯 **「딩–동–딩–동」** 으로 번갈아 나는 편이 훨씬 정돈돼 들린다.
//    무엇에 맞았는지는 화면을 보면 알기 때문에, 소리까지 종류를 나눌 이유가 없다.
//    ⚠️ 예외는 **벽돌을 쳤는데 안 깨졌을 때** 하나 — 이건 화면만 봐서는 알기 어렵고
//       「아직 남았다」를 알려야 하므로 묵직한 소리를 따로 쓴다.
//
//  주요 로직 : 소리마다 **볼륨을 따로 준다.**
//    원본 파일의 진폭이 제각각이라(45~72%) 여기서 균형을 맞춘다.
//
//  주요 로직 : **같은 갈래는 최소 간격을 둔다.**
//    무적공이 한 프레임에 벽돌을 여러 개 부수면 소리가 겹쳐 터진다.
//    간격 안에 다시 들어온 소리는 버린다.
//
//  주요 로직 : 재생기(플레이어)를 미리 여러 개 만들어 돌려 쓴다.
//    하나로 돌리면 앞 소리가 끊기고, 매번 새로 만들면 소리가 늦게 난다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:audioplayers/audioplayers.dart';

import 'brick_state.dart';

/// 소리 갈래 — **겹침 방지는 이 단위로** 센다.
/// 사건 종류가 아니라 갈래로 묶어야, 번갈아 나는 충돌음이 서로를 막지 않는다.
enum _Ch { hit, brickHit, ballLost, item, launch }

/// 부딪힐 때 번갈아 나는 두 소리 — 딩 · 동
///
/// 주요 로직 : 두 소리의 볼륨을 **같게** 둔다. 한쪽만 크면 번갈이가 아니라
///   「큰 소리 뒤에 작은 소리」로 들려서 리듬이 깨진다.
const List<String> _hitPair = ['audio/paddle.wav', 'audio/wall.wav'];
const double _hitVolume = 0.38;

/// 갈래별 최소 간격(밀리초)
const Map<_Ch, int> _gapMs = {
  _Ch.hit: 45,
  _Ch.brickHit: 45,
  _Ch.ballLost: 300,
  _Ch.item: 120,
  _Ch.launch: 150,
};

/// 번갈이 소리를 쓰지 않는 사건 — 파일과 볼륨을 따로 갖는다
const Map<GameEventType, (String, double, _Ch)> _solo = {
  // 벽돌을 쳤는데 안 깨짐 — 묵직하게. 내구도에 따라 음을 더 낮춘다
  GameEventType.brickHit: ('audio/brick_hit.wav', 0.55, _Ch.brickHit),

  GameEventType.ballLost: ('audio/ball_lost.wav', 0.90, _Ch.ballLost),
  GameEventType.itemHelp: ('audio/item_help.wav', 0.70, _Ch.item),
  GameEventType.itemHarm: ('audio/item_harm.wav', 0.70, _Ch.item),
  GameEventType.launch: ('audio/launch.wav', 0.50, _Ch.launch),
};

/// 번갈이 소리로 처리하는 사건 — 벽 · 패들 · 벽돌 깨짐
const Set<GameEventType> _hitEvents = {
  GameEventType.wallHit,
  GameEventType.paddleHit,
  GameEventType.brickBroken,
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

  /// 번갈이 차례 — 딩(0) ↔ 동(1)
  int _alt = 0;

  /// 갈래별 마지막 재생 시각 — 겹침 방지용
  final Map<_Ch, DateTime> _last = {};

  bool muted = false;

  /// 이번 프레임에 일어난 사건들을 소리로 낸다.
  void playAll(List<GameEvent> events) {
    if (muted) return;
    for (final e in events) {
      _play(e);
    }
  }

  void _play(GameEvent e) {
    final String file;
    final double volume;
    final _Ch ch;
    var rate = 1.0;

    if (_hitEvents.contains(e.type)) {
      file = _hitPair[_alt];
      volume = _hitVolume;
      ch = _Ch.hit;
    } else {
      final s = _solo[e.type];
      if (s == null) return;
      file = s.$1;
      volume = s.$2;
      ch = s.$3;
      if (e.type == GameEventType.brickHit) rate = _hitRate[e.hp] ?? 1.0;
    }

    final now = DateTime.now();
    final last = _last[ch];
    if (last != null &&
        now.difference(last).inMilliseconds < (_gapMs[ch] ?? 40)) {
      return; // 너무 붙어 있으면 버린다
    }
    _last[ch] = now;

    // 실제로 소리를 낸 경우에만 차례를 넘긴다.
    // 버려진 소리에서 넘기면 같은 소리가 연달아 나 번갈이가 깨진다.
    if (ch == _Ch.hit) _alt = 1 - _alt;

    final player = _pool[_next];
    _next = (_next + 1) % _pool.length;

    // 실패해도 게임은 계속되어야 한다 — 소리는 곁가지다.
    // (웹은 첫 조작 전에 재생이 막혀 있어 여기서 예외가 날 수 있다)
    player.setPlaybackRate(rate).catchError((_) {});
    player.play(AssetSource(file), volume: volume).catchError((_) {});
  }

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}
