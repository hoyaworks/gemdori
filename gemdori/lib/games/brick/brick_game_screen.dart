// ═══════════════════════════════════════════════════════════════════
//  brick_game_screen.dart — 게임 루프 · 입력 · 화면 배치
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 매 프레임 흐른 시간을 재서 BrickState.update() 에 넘기고,
//              마우스·터치·키보드 입력을 상태에 전달하고, 화면을 구성한다
//  제외 사항 : 게임 규칙 (전부 BrickState 안에 있다)
//
//  주요 로직 : 시간(dt)으로 움직인다 — 한 프레임에 몇 픽셀이 아니라 초당 몇 픽셀.
//    프레임 수로 움직이면 60fps 기기와 120fps 기기에서 공 속도가 2배 차이난다.
//
//  주요 로직 : dt 에 상한(1/30초)을 둔다 — 창을 끌거나 다른 탭에 갔다 오면
//    흐른 시간이 갑자기 커지는데, 그대로 넣으면 공이 한 번에 화면을 가로질러
//    벽돌·패들을 전부 지나쳐 버린다.
//
//  주요 로직 : 화면에 띄우는 것은 GameStatus 하나로만 갈린다.
//    ready → STAGE n 또는 발사 안내 / gameOver → GAME OVER / cleared → CLEARED.
//    상태를 화면 쪽에서 따로 만들지 않으므로 규칙과 화면이 어긋날 일이 없다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/dev_mode.dart';
import '../../app/game_loading.dart';
import 'brick_painter.dart';
import 'brick_state.dart';
import 'dev_panel.dart';
import 'sound.dart';

class BrickGameScreen extends StatefulWidget {
  const BrickGameScreen({super.key});

  @override
  State<BrickGameScreen> createState() => _BrickGameScreenState();
}

class _BrickGameScreenState extends State<BrickGameScreen>
    with SingleTickerProviderStateMixin, GameLoadingMixin {
  late final Ticker _ticker;
  late BrickState _state;
  Duration _lastTick = Duration.zero;

  /// 주요 로직 : 초점(FocusNode)을 필드로 들고 있는다.
  ///   build() 안에서 new 로 만들면 매 프레임 새 노드가 생겨 초점이 계속 날아가고,
  ///   그 결과 키보드 입력(스페이스)이 아예 들어오지 않는다. (2026-09-02 수정)
  final FocusNode _focusNode = FocusNode();

  /// 효과음. 상태가 남긴 사건을 매 프레임 가져가 재생한다
  final GameSound _sound = GameSound();

  /// 개발자 패널에 띄울 최근 사건.
  ///
  /// 주요 로직 : 사건은 `takeEvents()` 로 **한 번 가져가면 비워진다.**
  ///   소리와 로그가 따로 부르면 둘 중 하나만 받게 되므로,
  ///   여기서 한 번 받아 두 곳에 나눠 준다.
  ///
  /// 주요 로직 : 패널이 없으면 **쌓지도 않는다** — 아무도 안 보는 목록을
  ///   매 프레임 채우게 된다. 판단은 `DevPanel` 이 한다.
  final EventLog _log = EventLog();

  /// 경기장 크기 단계 (치트). 기본은 상한 그대로라 **평소 동작과 같다**
  FieldPreset _preset = FieldPreset.large;

  /// 지금 패널이 떠 있는가 — build 에서 정해 두고 게임 루프가 읽는다
  bool _showPanel = false;

  /// 사건 로그를 쌓을 것인가 — **기본 꺼짐** (2026-09-10).
  /// 켜 두면 갱신할 때마다 열두 줄의 글자 배치를 다시 잰다.
  /// ⚠️ 「그 비용이 게임 프레임에 얹혀 공이 밀린다」는 **디버그 모드에서 본 것**이다 —
  ///   profile 에서는 문제없었다 (2026-09-11). 필요할 때만 켜는 방식은 해가 없어 그대로 둔다.
  bool _logOn = false;

  /// 개발자 패널은 **초당 10번만** 새로 만든다 — 그사이에는 같은 위젯을 그대로 넘긴다.
  ///
  /// ⭐ 주요 로직 : 게임 루프가 매 프레임 `setState` 를 부르므로, 그냥 두면 패널도
  ///   **매 프레임 통째로 다시 만들어지고 다시 재어진다.** 평소에는 값이 싸지만
  ///   아이템을 먹는 순간(로그 한 줄·효과 한 칸이 함께 늘어남) 배치 계산이 한꺼번에 몰려
  ///   **공이 눈에 띄게 밀렸다** (2026-09-10 — 패널을 숨기면 증상이 사라졌다).
  /// ⚠️ 이 증상은 **디버그 모드의 첫 실행 값**이었다 — profile 에서는 없다 (2026-09-11).
  ///   갱신을 아끼는 구조는 해가 없고 디버그로 개발할 때 여전히 도움이 돼 그대로 둔다.
  ///   같은 위젯 인스턴스를 다시 넘기면 Flutter 가 그 아래를 통째로 건너뛴다.
  /// ⚠️ 값이 늦게 보이면 안 되는 것(크기 단계·치트)은 [_dropPanelCache] 로 즉시 지운다.
  Widget? _panelCache;
  Duration _panelAt = Duration.zero;

  static const _panelInterval = Duration(milliseconds: 100);

  void _dropPanelCache() => _panelCache = null;

  /// ⭐ **이 게임이 미리 받아 둘 것** — 로딩 막의 규칙 자체는 `GameLoadingMixin` 에 있다.
  ///   벽돌깨기는 소리뿐이다. 나중에 이미지·폰트가 생기면 여기 한 줄씩 늘린다.
  @override
  Future<void> prepareGame() => _sound.warmUp();

  @override
  void initState() {
    super.initState();
    _state = BrickState(fieldSize: const Size(320, 480));
    _ticker = createTicker(_onTick)..start();
    startPreparing();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    final step = dt.clamp(0.0, 1 / 30);
    setState(() => _state.update(step));
    // 사건은 가져가면서 비워진다 — 화면이 매 프레임 한 번만 부른다
    final events = _state.takeEvents();
    _sound.playAll(events);
    if (_showPanel && _logOn) _log.addAll(events);
  }

  void _movePaddle(Offset localPos) {
    if (!ready) return; // 준비 중에는 조작을 받지 않는다
    if (_state.paused) return; // 멈춘 동안에는 패들도 따라오지 않는다
    setState(() => _state.movePaddleTo(localPos.dx));
  }

  /// 터치·클릭·스페이스 — 대기 중일 때 공을 쏘는 것 하나뿐이다.
  ///
  /// 주요 로직 : 끝난 화면에서는 아무 반응도 하지 않는다.
  ///   화면 아무 곳이나 눌러 다시 시작되면 홈/다시시작 선택 버튼을 누를 새가 없다.
  void _primaryAction() {
    if (!ready) return; // 준비 중에는 발사되지 않는다
    // 일시정지 중이면 푸는 것이 먼저다 (2026-09-04).
    // 여기서 걸러 내지 않으면 푸는 동작이 그대로 발사로 이어진다.
    if (_state.paused) {
      setState(_state.resume);
      return;
    }
    if (_state.status != GameStatus.ready) return;
    setState(_state.launch);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 준비 중이면 게임 화면을 **이미 그려 둔 채로** 그 위가 덮인다
    return wrapWithLoading(_gameScaffold());
  }

  Widget _gameScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
        // 상단 바를 낮춰 경기장 세로를 벌었다 (2026-09-07). 기본 56 → 44
        toolbarHeight: 44,
        title: Row(
          children: [
            for (var i = 0; i < BrickState.maxLives; i++)
              Icon(
                i < _state.lives ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: const Color(0xFFFF6B6B),
              ),
            const SizedBox(width: 16),
            Text('${_state.score}'),
            const SizedBox(width: 16),
            _speedLabel(),
            const SizedBox(width: 16),
            // 걸려 있는 효과 — **버프만** 올린다 (장비·즉발은 화면이 이미 보여준다).
            // 목록·순서 판단은 BrickState.hudEffects 가 하고, 여기서는 그리기만.
            for (final t in _state.hudEffects)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Opacity(
                  opacity: _state.effectBlinkOn(t) ? 1 : 0.25,
                  child: ItemMark(t),
                ),
              ),
          ],
        ),
        actions: [
          // 음소거 — 소리는 곁가지라 언제든 끌 수 있어야 한다
          IconButton(
            icon: Icon(_sound.muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () => setState(() => _sound.muted = !_sound.muted),
          ),
          // 일시정지 — 멈춰 있는 동안에는 버튼 자체를 감춘다.
          // 화면 아무 곳이나 눌러 푸는 방식이라, 버튼이 남아 있으면
          // 「이 버튼을 다시 눌러야 하나」로 읽힌다.
          if (!_state.paused && _state.canPause)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () => setState(_state.pause),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_state.restart),
          ),
        ],
      ),
      // 하단 치트 바는 패널로 옮겼다 (2026-09-07) — 경기장 세로가 40px 늘었다
      // SafeArea — 안드로이드 하단 버튼·노치에 경기장이 가리지 않게 (2026-09-07)
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (e) {
              if (e is! KeyDownEvent) return;
              // ⭐ 막은 **화면만 가린다.** 키보드는 막 아래로 그대로 들어오므로
              //   여기서 따로 끊어야 한다 — 안 그러면 스페이스로 발사돼 버린다
              if (!ready) return;
              if (e.logicalKey == LogicalKeyboardKey.space) {
                _primaryAction();
                return;
              }
              // 크기 전환 1·2·3 — 패널이 안 뜨는 **좁은 화면에서도** 되게 키를 남긴다.
              // 단 개발 모드일 때만 — 실서비스에서 이용자가 누르면 안 된다
              if (!devMode) return;
              final p = _presetKeys[e.logicalKey];
              if (p != null) _setPreset(p);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 패널을 띄울지 **먼저** 정한다 — 게임에 줄 폭이 여기서 갈린다 (2026-09-07).
                // 실서비스 빌드면 visibleIn 이 늘 false 라, 이 아래는 게임만 남는다.
                final showPanel = DevPanel.visibleIn(constraints.maxWidth);
                _showPanel = showPanel;
                final gameWidth = DevPanel.gameWidth(constraints.maxWidth);

                // 경기장은 2:3 고정. 남는 공간은 배경색으로 비운다 (2026-09-07 재조정).
                // 입력 좌표가 경기장 기준이 되도록 SizedBox **안쪽**에 붙인다.
                final size = BrickState.fitField(
                  Size(gameWidth, constraints.maxHeight),
                  maxHeight: BrickState.presetHeight(_preset),
                );
                if (size != _state.fieldSize) {
                  _state.resize(size);
                }
                final field = Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: MouseRegion(
                      onHover: (e) => _movePaddle(e.localPosition),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (e) => _movePaddle(e.localPosition),
                        onTapDown: (e) {
                          _focusNode.requestFocus(); // 클릭 후에도 스페이스가 먹도록
                          _movePaddle(e.localPosition);
                          _primaryAction();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              size: size,
                              painter: BrickPainter(_state),
                            ),
                            _itemFlash(),
                            _overlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                if (!showPanel) return field;
                // stretch — 패널이 세로를 꽉 채워야 안쪽 로그 목록이 높이를 갖는다
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: DevPanel.gap),
                    _panel(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 상단 속도 표시 — `SPEED ▲2` 처럼 **항상** 보여 준다.
  ///
  /// 주요 로직 : 색·굵기는 바꾸지 않고 **깜빡임 하나로만** 알린다 (2026-09-03).
  ///   ① 아이템으로 바뀐 직후 두 번 · ② 원래대로 돌아가기 2초 전
  ///   스테이지가 넘어가며 기본 속도가 달라지는 것은 아무 효과 없이 값만 바뀐다.
  Widget _speedLabel() {
    return Opacity(
      opacity: _state.speedBlinkOn ? 1 : 0.25,
      child: Text(
        'SPEED ${_state.speedMark}',
        style: const TextStyle(fontSize: 14, color: Color(0xFFBFC7D5)),
      ),
    );
  }

  /// 먹은 아이템을 화면 가운데 잠깐 크게 띄운다.
  ///
  /// 주요 로직 : **전 종류**를 띄운다 (2026-09-03 확대).
  ///   상단 표시줄은 「지금 걸려 있는 것」을, 이 표시는 「방금 먹은 것」을 알린다.
  ///   뜻이 다르므로 상단에 남는 아이템이라고 해서 뺄 이유가 없다.
  ///   진하기 계산은 BrickState 가 하므로 여기서는 그리기만 한다.
  Widget _itemFlash() {
    final t = _state.flashItem;
    if (t == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: _state.itemFlashOpacity.clamp(0.0, 1.0),
          child: ItemMark(t, size: 64),
        ),
      ),
    );
  }

  /// 주요 로직 : 화면에 띄우는 것은 GameStatus 하나로만 갈린다.
  ///   ready 이면서 첫 안내일 때만 STAGE n 을 띄우고,
  ///   놓친 뒤 다시 대기할 때는 아무것도 띄우지 않는다 — 조작법은 이미 익혔으므로.
  Widget _overlay() {
    // 일시정지가 무엇보다 앞선다 — 멈춘 동안에는 이것만 보인다.
    // 글자 모양은 GAME OVER · CLEARED 와 같은 _label() 을 쓰고,
    // 깜빡임으로 「멈춰 있다」를 표현한다.
    if (_state.paused) {
      return Center(
        child: Opacity(
          opacity: _state.pauseBlinkOn ? 1 : 0.15,
          child: _label('PAUSE'),
        ),
      );
    }
    switch (_state.status) {
      case GameStatus.playing:
        return const SizedBox.shrink();
      case GameStatus.ready:
        if (!_state.stageIntro) return const SizedBox.shrink();
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _label(_state.isSampleStage ? 'SAMPLE' : 'STAGE ${_state.stage}'),
              // 조작 안내는 첫 스테이지에서만 — 그 뒤로는 이미 익혔다
              if (_state.stage <= 1) ...[
                const SizedBox(height: 12),
                const Text(
                  'TAP OR SPACE TO START',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ],
          ),
        );
      case GameStatus.gameOver:
        return _endOverlay('GAME OVER');
      case GameStatus.cleared:
        return _endOverlay('CLEARED');
    }
  }

  /// 끝난 화면 — 안내 한 줄과 선택 버튼 두 개(홈 · 다시 시작).
  /// GAME OVER 와 CLEARED 는 문구만 다르고 동작은 같게 맞춘다.
  Widget _endOverlay(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(text),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _endButton(
                icon: Icons.home,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 20),
              _endButton(
                icon: Icons.refresh,
                onPressed: () => setState(_state.restart),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _endButton({required IconData icon, required VoidCallback onPressed}) {
    return IconButton.filledTonal(
      iconSize: 28,
      padding: const EdgeInsets.all(14),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  // ─── 치트 (개발자 패널에서 부른다) ──────────────────────────
  //
  //  상세 설명 : 각 상황을 손으로 만들려면 한 판을 다 해야 해서 확인이 느리다.
  //    버튼으로 바로 이동한다. 목숨·점수 정합성은 따지지 않는다.
  //
  //  ⛔ **개발 전용.** 지우지 않아도 실서비스 빌드에서는 부르는 곳이 없어진다
  //     (패널이 통째로 빠지고, 숫자키도 devMode 에서 막힌다).
  //
  //  주요 로직 : 실행 뒤 **초점을 게임으로 되돌린다.** 안 되돌리면 버튼을
  //    한 번 누른 순간부터 스페이스·숫자키가 버튼으로 가서 게임에 안 들어온다.

  void _runCheat(VoidCallback action) {
    _dropPanelCache();
    setState(action);
    _focusNode.requestFocus();
  }

  /// 개발자 패널 — [_panelInterval] 마다만 새로 만든다. 위 [_panelCache] 설명 참조.
  Widget _panel() {
    if (_panelCache == null || _lastTick - _panelAt >= _panelInterval) {
      _panelAt = _lastTick;
      _panelCache = DevPanel(
        state: _state,
        log: _log,
        preset: _preset,
        onCheat: _runCheat,
        onPreset: _setPreset,
        logOn: _logOn,
        onToggleLog: _toggleLog,
      );
    }
    return _panelCache!;
  }

  /// 로그를 껐다 켠다. 끌 때는 쌓인 줄도 비운다 — 다시 켰을 때 옛 사건이 섞이면 헷갈린다
  void _toggleLog() {
    _dropPanelCache();
    setState(() {
      _logOn = !_logOn;
      if (!_logOn) _log.clear();
    });
    _focusNode.requestFocus();
  }

  /// 경기장 크기 단계를 바꾼다.
  ///
  /// 주요 로직 : 크기 자체는 여기서 계산하지 않는다. 단계만 바꿔 두면
  ///   다음 build 의 `fitField` 가 상한으로 반영하고, `resize()` 가
  ///   날아가던 공의 속력까지 다시 맞춘다 — 계산이 한 군데에만 있다.
  // 2026-09-11 : 이 설명이 코드를 옮기다 `_panel()` 위에 붙어 있던 것을 제자리로 돌렸다
  void _setPreset(FieldPreset p) {
    _dropPanelCache();
    setState(() => _preset = p);
    _focusNode.requestFocus();
  }

  /// 숫자키 ↔ 크기 단계
  static final Map<LogicalKeyboardKey, FieldPreset> _presetKeys = {
    LogicalKeyboardKey.digit1: FieldPreset.small,
    LogicalKeyboardKey.digit2: FieldPreset.medium,
    LogicalKeyboardKey.digit3: FieldPreset.large,
    LogicalKeyboardKey.numpad1: FieldPreset.small,
    LogicalKeyboardKey.numpad2: FieldPreset.medium,
    LogicalKeyboardKey.numpad3: FieldPreset.large,
  };

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 2,
    ),
  );
}
