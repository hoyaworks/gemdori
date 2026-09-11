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
//  ⭐ 주요 로직 : **파일마다 전용 재생기를 둔다** (2026-09-07 재설계).
//    예전에는 재생기 여러 개를 **돌려 썼다**. 그러면 재생기가 낼 파일이 매번 바뀌어,
//    **그 재생기가 그 파일을 처음 내는 순간**마다 파일을 물리는 일이 벌어진다.
//    지금은 재생기가 **자기 파일 하나만** 평생 낸다 — 물리는 일이 데우기 때 끝나고,
//    재생은 「처음으로 되감아 다시 틀기」뿐이라 게임 중에 새로 할 일이 없다.
//    겹칠 수 있는 충돌음(딩·동)만 재생기를 두 개씩 준다.
//    ⚠️ 원래는 「소리 종류가 처음 날 때 공이 뚝 끊기는」 증상의 대책이었으나,
//       소리를 통째로 꺼도 증상이 남아 **소리는 원인이 아니었다** (2026-09-10).
//       그 증상은 **디버그 모드의 첫 실행 값**이었다 (2026-09-11 profile 확인).
//       구조 자체는 단순하고 해가 없어 그대로 둔다.
//
//  주요 로직 : **소리 파일을 미리 물려 둔다**(warmUp · 2026-09-07).
//    첫 재생 순간에 파일을 내려받고 디코딩하는 일을 **로딩 막 뒤로** 옮긴다.
//    실패해도 그냥 넘어간다 — 소리는 곁가지다.
//    ⚠️ 처음에는 「브라우저를 켜고 맨 처음 발사할 때만 버벅이는」 증상의 원인으로 봤으나,
//       소리를 통째로 끄고도 첫 발사가 멀쩡했다 — **해결한 것은 로딩 막 쪽**이었다 (2026-09-10).
//       데우기는 해가 없어 그대로 둔다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:audioplayers/audioplayers.dart';

import 'brick_state.dart';

/// 소리 갈래 — **겹침 방지는 이 단위로** 센다.
/// 사건 종류가 아니라 갈래로 묶어야, 번갈아 나는 충돌음이 서로를 막지 않는다.
enum _Ch { hit, brickHit, ballLost, item, launch }

/// 부딪힐 때 번갈아 나는 두 소리 — **딩(paddle) → 동(wall) 순서로 시작**
///
/// 주요 로직 : 두 소리의 볼륨을 **같게** 둔다. 한쪽만 크면 번갈이가 아니라
///   「큰 소리 뒤에 작은 소리」로 들려서 리듬이 깨진다.
const String _sfxDing = 'audio/paddle.wav';
const String _sfxDong = 'audio/wall.wav';
const List<String> _hitPair = [_sfxDing, _sfxDong];
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

  // 발사 — **번갈이 첫 소리(딩)와 같은 파일**을 쓴다 (2026-09-07).
  //   발사가 리듬의 첫 박이 되어 「딩(발사) – 동 – 딩 – 동」으로 이어진다.
  GameEventType.launch: (_sfxDing, _hitVolume, _Ch.launch),
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

/// 쓰는 소리 파일 전부 — 데우기 대상.
///
/// 주요 로직 : 위 표들에서 **뽑아 만든다.** 손으로 또 적으면
///   소리를 하나 추가했을 때 데우기에서만 빠져 그 소리만 늦게 난다.
final List<String> _allFiles = {
  ..._hitPair,
  ..._solo.values.map((v) => v.$1),
}.toList();

/// 파일마다 둘 재생기 수 — 겹쳐 날 수 있는 충돌음만 두 개.
///
/// 주요 로직 : 하나로 두면 앞 소리가 채 끝나기 전에 다시 틀 때 **잘린다.**
///   나머지 소리는 서로 45ms 이상 떨어져 있어 하나로 충분하다.
int _playersFor(String file) => _hitPair.contains(file) ? 2 : 1;

class GameSound {
  GameSound()
      : _byFile = {
          for (final f in _allFiles)
            f: List.generate(_playersFor(f), (_) => AudioPlayer()),
        } {
    for (final players in _byFile.values) {
      for (final p in players) {
        p.setReleaseMode(ReleaseMode.stop);
      }
    }
  }

  /// 재생기마다 **자기 파일을 물려 둔다** — 소리는 나지 않는다.
  ///
  /// 주요 로직 : 이 한 번으로 끝난다. 재생기는 평생 이 파일만 내므로
  ///   게임 중에 다시 물릴 일이 없다.
  ///   ⚠️ 시간이 걸리므로 **로딩 막 뒤에서** 돌린다 (화면 쪽 `prepareGame()`).
  Future<void> warmUp() async {
    for (final entry in _byFile.entries) {
      for (final player in entry.value) {
        try {
          await player.setSource(AssetSource(entry.key));
        } catch (_) {
          // 데우기 실패는 무시한다 — 소리는 곁가지고, 실패해도 게임은 돈다
        }
      }
    }
  }

  /// 파일 → 그 파일 전용 재생기들
  final Map<String, List<AudioPlayer>> _byFile;

  /// 파일별 다음 차례 (재생기가 둘인 것만 실제로 돈다)
  final Map<String, int> _turn = {};

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

    // 발사음이 곧 첫 박(딩)이므로, 다음 충돌은 동(wall)부터 시작한다.
    // 이렇게 해야 발사 직후 같은 소리가 두 번 겹치지 않는다.
    if (ch == _Ch.launch) _alt = 1;

    final players = _byFile[file];
    if (players == null) return;
    final i = (_turn[file] ?? 0) % players.length;
    _turn[file] = i + 1;
    final player = players[i];

    // 주요 로직 : **다시 틀지 않고 되감아 튼다.**
    //   `play(AssetSource…)` 는 파일을 다시 물리는 길이라 게임 중에는 피한다.
    //   이미 물려 둔 것을 처음으로 되감아(`seek`) 재생(`resume`)만 한다.
    //
    // 실패해도 게임은 계속되어야 한다 — 소리는 곁가지다.
    // (웹은 첫 조작 전에 재생이 막혀 있어 여기서 예외가 날 수 있다)
    player.setVolume(volume).catchError((_) {});
    player.setPlaybackRate(rate).catchError((_) {});
    player.seek(Duration.zero).catchError((_) {});
    player.resume().catchError((_) {});
  }

  void dispose() {
    for (final players in _byFile.values) {
      for (final p in players) {
        p.dispose();
      }
    }
  }
}
