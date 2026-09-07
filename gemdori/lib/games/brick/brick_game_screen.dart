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

import 'brick_painter.dart';
import 'brick_state.dart';
import 'sound.dart';

class BrickGameScreen extends StatefulWidget {
  const BrickGameScreen({super.key});

  @override
  State<BrickGameScreen> createState() => _BrickGameScreenState();
}

class _BrickGameScreenState extends State<BrickGameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late BrickState _state;
  Duration _lastTick = Duration.zero;

  /// 주요 로직 : 초점(FocusNode)을 필드로 들고 있는다.
  ///   build() 안에서 new 로 만들면 매 프레임 새 노드가 생겨 초점이 계속 날아가고,
  ///   그 결과 키보드 입력(스페이스)이 아예 들어오지 않는다. (2026-09-02 수정)
  final FocusNode _focusNode = FocusNode();

  /// 효과음. 상태가 남긴 사건을 매 프레임 가져가 재생한다
  final GameSound _sound = GameSound();

  @override
  void initState() {
    super.initState();
    _state = BrickState(fieldSize: const Size(320, 480));
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    final step = dt.clamp(0.0, 1 / 30);
    setState(() => _state.update(step));
    // 사건은 가져가면서 비워진다 — 화면이 매 프레임 한 번만 부른다
    _sound.playAll(_state.takeEvents());
  }

  void _movePaddle(Offset localPos) {
    if (_state.paused) return; // 멈춘 동안에는 패들도 따라오지 않는다
    setState(() => _state.movePaddleTo(localPos.dx));
  }

  /// 터치·클릭·스페이스 — 대기 중일 때 공을 쏘는 것 하나뿐이다.
  ///
  /// 주요 로직 : 끝난 화면에서는 아무 반응도 하지 않는다.
  ///   화면 아무 곳이나 눌러 다시 시작되면 홈/다시시작 선택 버튼을 누를 새가 없다.
  void _primaryAction() {
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
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
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
      bottomNavigationBar: SafeArea(child: _cheatBar()),
      // SafeArea — 안드로이드 하단 버튼·노치에 경기장이 가리지 않게 (2026-09-07)
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
              _primaryAction();
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 경기장은 9:16 고정. 남는 공간은 배경색으로 비운다 (2026-09-04).
              // 입력 좌표가 경기장 기준이 되도록 SizedBox **안쪽**에 붙인다.
              final size = BrickState.fitField(
                Size(constraints.maxWidth, constraints.maxHeight),
              );
              if (size != _state.fieldSize) {
                _state.resize(size);
              }
              return Center(
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
            },
            ),
          ),
        ),
      ),
    );
  }

  /// 상단 속도 표시 — `SPEED (▲▲)` 로 **항상** 보여 준다.
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
  /// 주요 로직 : **8종 전부** 띄운다 (2026-09-03 확대).
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
              _label(_state.isSampleStage
                  ? 'SAMPLE'
                  : 'STAGE ${_state.stage}'),
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

  // ─── 테스트용 (나중에 가리거나 지울 것) ────────────────────────
  //
  //  상세 설명 : 각 상황을 손으로 만들려면 한 판을 다 해야 해서 확인이 느리다.
  //    이 줄의 버튼으로 바로 이동한다. 목숨·점수 정합성은 따지지 않는다.
  Widget _cheatBar() {
    return SafeArea(
      child: Container(
        color: const Color(0xFF161B22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 테스트용 — 경기장 크기와 배율. 창을 움직일 때 값이 바뀌는지 눈으로 본다
            SizedBox(
              width: 108,
              child: Text(
                '${_state.fieldSize.width.round()}×${_state.fieldSize.height.round()}'
                '  ×${_state.scale.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFF7BE38B)),
              ),
            ),
            _cheatButton('SAMPLE', _state.debugLoadSampleStage),
            _cheatIcon(
              Icons.chevron_left,
              () => _state.debugGoToStage(_state.stage - 1),
            ),
            SizedBox(
              width: 64,
              child: Text(
                _state.isSampleStage ? 'SAMPLE' : 'STAGE ${_state.stage}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
            _cheatIcon(
              Icons.chevron_right,
              () => _state.debugGoToStage(_state.stage + 1),
            ),
            _cheatButton('GAME OVER', _state.debugGameOver),
            _cheatButton('CLEARED', _state.debugClearStage),
          ],
        ),
      ),
    );
  }

  Widget _cheatIcon(IconData icon, VoidCallback action) {
    return IconButton(
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: Colors.white60,
      icon: Icon(icon),
      onPressed: () {
        setState(action);
        _focusNode.requestFocus();
      },
    );
  }

  Widget _cheatButton(String text, VoidCallback action) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: Colors.white60,
      ),
      onPressed: () {
        setState(action);
        _focusNode.requestFocus();
      },
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

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
