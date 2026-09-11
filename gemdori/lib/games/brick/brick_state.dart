// ═══════════════════════════════════════════════════════════════════
//  brick_state.dart — 게임 규칙 전부
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 공·패들·벽돌의 위치와 충돌, 점수·목숨·스테이지 진행
//  제외 사항 : 화면 그리기 · 사용자 입력 · 시간 측정 (각각 Painter, Screen 담당)
//
//  상세 설명
//    Flutter 위젯을 하나도 쓰지 않기 때문에 화면 없이 이 파일만 테스트할 수 있다.
//    규칙이 계산과 화면에 섞여 있으면 "가장자리에 맞으면 몇 도로 튀는가" 같은 것을
//    눈으로만 확인하게 되고, 나중에 손대기가 무서워진다.
//
//  주요 로직 : 게임 진행을 4가지 상태로만 관리한다 (GameStatus)
//    ready    공이 패들 위에 얹혀 대기. 패들을 움직이면 공도 같이 움직인다
//    playing  공이 날아다니는 중 — update() 가 실제로 계산하는 유일한 상태
//    cleared  벽돌을 다 깸
//    gameOver 목숨을 다 씀
//    화면은 이 값 하나만 보고 무엇을 띄울지 정한다. 조건이 여기저기 흩어지지 않는다.
//
//  주요 로직 : 면에 부딪혔을 때의 「되꺾기」는 reflectJustCrossedFace() 하나로 통합돼 있다
//    (2026-09-04). 좌우 벽·위 벽·벽돌이 같은 식을 쓴다. **막 넘어선 경우에만** 쓸 수 있고,
//    이미 겹친 채 시작한 공에 쓰면 벽돌 위로 순간이동한다 — 함수 주석의 경고를 볼 것.
//
//  주요 로직 : update() 안의 판정 순서 — 순서가 곧 규칙이다
//    1 좌우 벽  2 위 벽  3 벽돌  4 패들  5 바닥(놓침)
//    벽돌을 패들보다 먼저 보는 이유 : 같은 프레임에 둘 다 닿는 일은 거의 없지만,
//    겹칠 경우 화면 위쪽에서 일어난 일을 먼저 반영하는 편이 눈에 자연스럽다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:ui';

import 'ball.dart';
import 'brick.dart';
import 'item.dart';

/// 게임 진행 상태
enum GameStatus { ready, playing, cleared, gameOver }

/// 경기장 크기 전환 단계 (치트 전용 · 2026-09-07).
/// 실제 값은 [BrickState.presetHeight] 에 있다
enum FieldPreset { small, medium, large }

/// 소리를 붙일 「방금 일어난 일」 (2026-09-04)
///
/// 주요 로직 : 상태(BrickState)는 **소리를 재생하지 않는다.** 무슨 일이 있었는지만 남긴다.
///   재생은 화면 쪽이 맡는다 — 여기서 오디오를 건드리면 화면 없이 도는
///   테스트가 전부 깨지고, 규칙과 연출이 한 덩어리로 엉킨다.
enum GameEventType {
  launch, // 발사
  wallHit, // 벽 반사
  paddleHit, // 패들 반사
  brickHit, // 벽돌에 맞았지만 안 깨짐
  brickBroken, // 벽돌 깨짐
  ballLost, // 공을 놓침
  itemHelp, // 도움 아이템 획득
  itemHarm, // 방해 아이템 획득
}

/// 일어난 일 하나. 벽돌 소리는 색(내구도)에 따라 음정을 달리하므로 값을 함께 싣는다.
class GameEvent {
  const GameEvent(this.type, {this.hp = 0});

  final GameEventType type;

  /// 벽돌 관련일 때의 내구도(1 파랑 · 2 노랑 · 3 빨강). 아니면 0
  final int hp;

  @override
  String toString() => hp == 0 ? '$type' : '$type(hp:$hp)';
}

/// 스테이지 한 개의 정의
class StageSpec {
  const StageSpec(this.rowHp, this.speedLevel, this.helpItems, this.harmItems);

  /// 위쪽 줄부터의 내구도. 길이가 곧 줄 수다. 1=파랑 2=노랑 3=빨강
  final List<int> rowHp;

  /// 공 속도 단계 — BrickState.speedTable 의 자리
  final int speedLevel;

  /// 이 스테이지에 심는 도움 아이템 개수
  final int helpItems;

  /// 이 스테이지에 심는 방해 아이템 개수
  final int harmItems;
}

/// **이번 프레임에 막 넘어선** 면에서 되꺾은 좌표 (2026-09-04 통합)
///
/// 한 축만 본다. `from`(프레임 시작) → `to`(막 이동한 자리) 로 가는 길에 `face` 를
/// 넘어섰을 때, 넘어간 만큼을 반대 방향으로 마저 보낸 좌표를 돌려준다.
/// 좌우 벽·위 벽·벽돌이 저마다 똑같은 식을 적고 있어 한 자리로 모았다.
///
/// 주요 로직 : 면에 **붙여 놓기만 하면** 부딪힌 프레임만 이동거리가 짧아
///   「멈칫 → 가속」으로 보인다. 넘어간 거리를 버리지 않고 접어 보내야
///   프레임마다 가는 거리가 일정하다.
///
/// ⚠️ **이미 면을 넘어선 채로 시작한 좌표에는 쓰면 안 된다.**
///   거울처럼 접는 계산이라 면에서 깊이 들어와 있을수록 반대편으로 그만큼 멀리 보낸다.
///   2026-09-04 에 실제로 사고가 났다 — 벽돌과 벽돌 사이 틈에 낀 공(이미 깊이 겹친 상태)이
///   충돌 뒤 **벽돌 위로 순간이동**했다. 그 경우는 되꺾지 말고 면에 붙여야 한다
///   (`_moveBall` 의 `if (!hitSide && !hitFace)` 분기).
///   전제가 깨진 채 부르면 테스트에서 바로 터지도록 assert 로 막아 둔다.
double reflectJustCrossedFace({
  required double from,
  required double to,
  required double face,
}) {
  assert(
    (from - face) * (to - face) <= 0,
    '되꺾기 전제 위반 — 이미 면을 넘어선 채 시작했다 '
    '(from=$from, to=$to, face=$face). 이 경우는 면에 붙여서 처리할 것.',
  );
  return 2 * face - to;
}

class BrickState {
  BrickState({
    required this.fieldSize,
    Random? random,
    this.stage = 1,
    GameStatus status = GameStatus.ready,
    Offset? ballPos,
    Offset? ballVelocity,
    double ballRadius = 8,
    double basePaddleWidth = 90,
    double paddleHeight = 12,
    double paddleBottomMargin = 24,
    double? paddleX,
    this.brickCols = 7,
    double brickTopMargin = 56,
    double brickSideMargin = 12,
    double brickGap = 6,
    double brickHeight = 20,
    this.refWidth = defaultRefWidth,
  })  : _random = random ?? Random(),
        _refBallRadius = ballRadius,
        _refPaddleWidth = basePaddleWidth,
        _refPaddleHeight = paddleHeight,
        _refPaddleBottomMargin = paddleBottomMargin,
        _refBrickTopMargin = brickTopMargin,
        _refBrickSideMargin = brickSideMargin,
        _refBrickGap = brickGap,
        _refBrickHeight = brickHeight,
        paddleX = paddleX ?? fieldSize.width / 2,
        status = GameStatus.ready {
    // loadStage() 가 공 위치와 상태를 기본값으로 맞춘 뒤,
    // 생성자에서 명시한 값이 있으면 그것으로 덮어쓴다.
    // (테스트에서 특정 상황을 바로 만들기 위한 통로)
    loadStage(stage);
    if (ballPos != null) this.ballPos = ballPos;
    if (ballVelocity != null) this.ballVelocity = ballVelocity;
    // loadStage() 가 ready 로 되돌린 뒤라서 초기화 목록으로는 대입할 수 없다.
    // ignore: prefer_initializing_formals
    this.status = status;
  }

  final Random _random;

  Size fieldSize;

  /// 살아 있는 공들. 보통 1개이고, 멀티볼 아이템에서 늘어난다.
  List<Ball> balls = [];

  // ── 크기 ─────────────────────────────────────────────────────────
  //
  // ⭐ 주요 로직 : 모든 크기는 **경기장 폭에 비례**한다 (2026-09-07).
  //   예전에는 패들 90px · 공 8px 처럼 고정 픽셀이었다. 그러면 화면이 클수록
  //   패들이 **상대적으로 작아져 어려워진다** — 공들여 맞춘 난이도를 기기가 흔든다.
  //   아래 `_ref*` 는 **기준 폭(refWidth)에서의 값**이고, 실제 값은 폭에 맞춰 늘고 준다.
  //   ⛔ 글자 크기는 예외 — 작아지면 못 읽으므로 화면 쪽에서 고정으로 둔다.
  static const double defaultRefWidth = 600;

  /// 이 경기장의 기준 폭. 테스트는 계산을 고정하려고 실제 폭과 같게 준다
  final double refWidth;

  /// 기준 폭 대비 배율
  double get scale => fieldSize.width / refWidth;

  final double _refBallRadius;
  final double _refPaddleWidth;
  final double _refPaddleHeight;
  final double _refPaddleBottomMargin;
  final double _refBrickTopMargin;
  final double _refBrickSideMargin;
  final double _refBrickGap;
  final double _refBrickHeight;

  double get ballRadius => _refBallRadius * scale;

  /// 떨어지는 아이템 반지름
  double get itemRadius => 9 * scale;

  /// 벽돌 위에 그리는 아이템 기호 반지름
  double get brickMarkRadius => 6 * scale;

  /// 공이 하나일 때를 위한 지름길 — 대부분의 규칙과 테스트가 공 1개를 다룬다.
  /// 공이 여러 개면 첫 번째 공을 가리킨다.
  Offset get ballPos => balls.isEmpty ? Offset.zero : balls.first.pos;
  set ballPos(Offset v) {
    if (balls.isEmpty) {
      balls = [Ball(pos: v, velocity: Offset.zero)];
    } else {
      balls.first.pos = v;
    }
  }

  Offset get ballVelocity =>
      balls.isEmpty ? Offset.zero : balls.first.velocity;
  set ballVelocity(Offset v) {
    if (balls.isEmpty) {
      balls = [Ball(pos: Offset.zero, velocity: v)];
    } else {
      balls.first.velocity = v;
    }
  }

  /// 아이템이 없을 때의 패들 폭
  double get basePaddleWidth => _refPaddleWidth * scale;

  /// 실제 패들 폭 — 확대 2배 / 축소 1/2
  double get paddleWidth {
    if (hasEffect(ItemType.paddleGrow)) return basePaddleWidth * 2;
    if (hasEffect(ItemType.paddleShrink)) return basePaddleWidth / 2;
    return basePaddleWidth;
  }

  double get paddleHeight => _refPaddleHeight * scale;

  /// 바닥에서 패들까지 띄우는 간격
  double get paddleBottomMargin => _refPaddleBottomMargin * scale;

  /// 패들 중심 x 좌표
  double paddleX;

  final int brickCols;
  double get brickTopMargin => _refBrickTopMargin * scale;
  double get brickSideMargin => _refBrickSideMargin * scale;
  double get brickGap => _refBrickGap * scale;
  double get brickHeight => _refBrickHeight * scale;

  /// 벽돌 목록. 깨진 것(hp = 0)도 목록에는 남겨 둔다.
  List<Brick> bricks = [];

  GameStatus status;
  int stage;

  /// 걸려 있는 효과 — 남은 시간(초). 무기한은 무한대.
  ///
  /// 주요 로직 : 종류를 열쇠로 쓰는 Map 이라 같은 효과가 두 번 들어갈 수 없다.
  ///   같은 것을 또 먹으면 시간형은 시간만 다시 채워지고, 무기한형은 그대로다.
  final Map<ItemType, double> effects = {};

  /// 현재 공 속도 단계 (speedTable 의 자리 · 0~4).
  ///
  /// 주요 로직 : 속도만 effects 맵이 아니라 **단계 값 하나로** 들고 있다.
  ///   아이템이 표 안에서 한 칸씩 누적으로 움직이는 규칙이라
  ///   「걸렸다/안 걸렸다」로는 표현이 안 된다 (2026-09-03 변경).
  int speedStage = 0;

  /// 속도 아이템 효과의 남은 시간(초). 0 이면 스테이지 기본 속도 상태다.
  /// 다 되면 몇 칸을 움직였든 **한 번에** 기본 단계로 돌아간다.
  double speedLeft = 0;

  /// 아이템으로 단계가 막 바뀌었음을 알리는 깜빡임의 남은 시간(초)
  double speedFlash = 0;

  /// 깜빡임 두 번 = 주기 0.5초 × 2
  static const double speedFlashSeconds = speedBlinkPeriod * 2;

  /// 방금 먹은 아이템 — 화면 가운데 잠깐 띄운다.
  /// 2026-09-03 부터 **전 종류** 대상 (예전에는 시간형을 뺐다)
  ItemType? flashItem;

  /// 그 표시의 남은 시간(초)
  double flashLeft = 0;

  static const double itemFlashSeconds = 2;

  /// 나타나는 데 걸리는 시간 — 사라지는 시간보다 훨씬 짧다
  static const double itemFlashInSeconds = 0.2;

  /// 반짝 표시의 진하기 (0~1).
  ///
  /// 주요 로직 : **빠르게 나타나고 천천히 사라진다** (2026-09-03).
  ///   갑자기 툭 튀어나오면 시선을 뺏기고, 나타나는 것까지 느리면
  ///   무엇을 먹었는지 알아보기 전에 이미 옅어져 있다.
  double get itemFlashOpacity {
    if (flashItem == null) return 0;
    final elapsed = itemFlashSeconds - flashLeft;
    if (elapsed < itemFlashInSeconds) return elapsed / itemFlashInSeconds;
    return flashLeft / (itemFlashSeconds - itemFlashInSeconds);
  }

  /// 무적 중 공 색이 바뀌는 주기(초)
  static const double ballFlashPeriod = 0.15;

  /// 무적 중 공 색 번호 (0~2). 무적이 아니면 null.
  ///
  /// 주요 로직 : 남은 시간으로 계산한다 — 별도 시계를 두지 않으려는 것 (2026-09-03).
  ///   효과가 걸린 뒤 흐른 시간을 주기로 나눠 순환시키므로,
  ///   무적을 다시 먹어 시간이 리셋되면 색도 처음부터 다시 돈다.
  ///   대충 하면 : 여기에 필드를 하나 더 두면 초기화 자리를 빠뜨려
  ///   무적이 끝난 뒤에도 색이 남는다.
  int? get invincibleColorIndex {
    final e = _invincibleElapsed;
    return e == null ? null : (e / ballFlashPeriod).floor() % 3;
  }

  /// 무적이 걸린 뒤 흐른 시간(초). 무적이 아니면 null
  double? get _invincibleElapsed {
    final left = effects[ItemType.invincibleBall];
    if (left == null) return null;
    return ItemType.invincibleBall.seconds - left;
  }

  /// 무적 중 공에 바깥 링을 두를 차례인가 — ● ↔ ◉ 를 오간다 (2026-09-04).
  ///
  /// 주요 로직 : 모양 주기는 색 주기의 **두 배**로 둔다.
  ///   색과 같은 속도로 바꾸면 초당 6~7번 형태가 흔들려 공을 눈으로 좇기 어렵다.
  bool get invincibleRingOn {
    final e = _invincibleElapsed;
    if (e == null) return false;
    return (e / (ballFlashPeriod * 2)).floor().isOdd;
  }

  /// 상단 표시줄에 올릴 효과 — **버프만, 번호순 고정** (2026-09-04).
  ///
  /// 주요 로직 : 규칙을 여기에 둔 이유가 있다.
  ///   예전에는 화면이 `effects` 를 통째로 뿌려서 장비(멀티공·패들 크기)까지 올라갔고,
  ///   **규칙이 코드 어디에도 없어** 문서와 조용히 어긋나 있었다.
  ///   나열 순서도 `effects` 의 삽입 순서(=먹은 순서)라 자리가 매번 바뀌었다.
  List<ItemType> get hudEffects =>
      ItemType.values.where((t) => t.isBuff && effects.containsKey(t)).toList();

  /// 경기장 가로세로 비율 — **2:3 고정** (2026-09-07 재조정)
  ///
  /// 상세 설명 : 9:16 → 3:4 → **2:3** 으로 두 번 옮겼다.
  ///   9:16 은 좌우가 답답했고, 3:4 는 상한이 걸리자 **위아래가 짧아 뭉툭해** 보였다.
  ///   2:3 이 그 사이다 — 세로로 긴 느낌은 살면서 좌우도 답답하지 않다.
  static const double fieldAspect = 2 / 3;

  /// 경기장 세로 상한(px) — **아무리 화면이 커도 이보다 커지지 않는다** (2026-09-07).
  ///
  /// 주요 로직 : 1366×768 노트북에서 **여유 있게 들어가는 크기**로 잡았다.
  ///   768 − 작업표시줄 48 − 브라우저 상단 100 − 앱 상단바 44 − 치트바 40 − 여백 12 ≈ 524.
  ///   거기서 조금 덜어 520 으로 둔다. (상단바를 56 → 44 로 낮춰 12px 을 벌었다)
  ///   상한이 없으면 큰 모니터에서 과하게 커져, 폰에서는 손가락 이동 거리가 늘고
  ///   PC 에서는 창을 움직일 때마다 크기가 따라 변한다.
  static const double maxFieldHeight = 520;

  /// 그때의 가로 상한 — 비율에서 저절로 나온다
  static double get maxFieldWidth => maxFieldHeight * fieldAspect;

  /// 주어진 공간 안에서 비율을 지키는 가장 큰 경기장 크기 (상한 적용).
  ///
  /// 주요 로직 : **화면 비율이 난이도가 되는 문제**를 막는다.
  ///   위아래로 길수록 공이 오가는 시간이 늘어 쉬워지고, 넓적하면 어려워진다.
  ///   비율을 고정하면 스테이지 표(속도·아이템 수)가 **모든 화면에서 그대로 유효**하다.
  ///   남는 공간은 배경색으로 비운다 — 늘리는 쪽은 전부 난이도를 건드린다.
  ///   [maxHeight] 로 상한을 더 낮출 수 있다 — 치트의 크기 전환(S·M·L)이 쓴다.
  ///   **낮추는 쪽으로만 쓴다.** 화면보다 크게 달라고 해도 들어가는 크기를 넘지 않는다.
  static Size fitField(Size available, {double maxHeight = maxFieldHeight}) {
    if (available.width <= 0 || available.height <= 0) return Size.zero;

    var h = available.height;
    var w = h * fieldAspect;
    if (w > available.width) {
      w = available.width;
      h = w / fieldAspect;
    }
    if (h > maxHeight) {
      h = maxHeight;
      w = h * fieldAspect;
    }
    return Size(w, h);
  }

  /// 크기 전환 단계 — 치트 전용 (2026-09-07)
  ///
  /// 주요 로직 : 이 버튼의 목적은 「크게 보기」가 아니라
  ///   **「화면 크기가 난이도를 바꾸지 않는가」를 눈으로 확인하는 것**이다.
  ///   그래서 값을 예쁜 수가 아니라 **실제로 만나는 크기**에 맞춰 잡았다.
  ///
  ///   large  520 — 상한 그대로. PC 브라우저에서 늘 걸리는 값이라 **기본값**
  ///   medium 440 — **폭 320px 폰의 실제 크기**(경기장 ≈293×440). 가장 작은 실기기
  ///   small  360 — 실기기보다 **한 단계 아래**. 최악을 미리 보는 값이자,
  ///                그 아래로는 벽돌 사이 간격(6px×0.4=2.4)과 아이템 기호가 뭉개져
  ///                눈으로 판별이 안 되는 **실용 하한**
  static double presetHeight(FieldPreset p) => switch (p) {
        FieldPreset.small => 360,
        FieldPreset.medium => 440,
        FieldPreset.large => maxFieldHeight,
      };

  /// 아직 화면이 가져가지 않은 사건들.
  ///
  /// 주요 로직 : **화면이 가져가면서 비운다**(takeEvents). 상태가 프레임 시작에 비우면,
  ///   update() 밖에서 일어나는 일(발사 등)이 읽히기도 전에 사라진다.
  final List<GameEvent> _events = [];

  void _emit(GameEventType t, {int hp = 0}) =>
      _events.add(GameEvent(t, hp: hp));

  /// 쌓인 사건을 가져가고 비운다. 화면이 매 프레임 한 번 부른다.
  List<GameEvent> takeEvents() {
    if (_events.isEmpty) return const [];
    final out = List<GameEvent>.from(_events);
    _events.clear();
    return out;
  }

  /// 일시정지 중인가 (2026-09-04)
  bool paused = false;

  /// 일시정지가 걸린 뒤 흐른 시간(초) — PAUSE 글자 깜빡임에만 쓴다
  double pauseElapsed = 0;

  /// PAUSE 글자를 지금 보일 것인가
  bool get pauseBlinkOn =>
      pauseElapsed % speedBlinkPeriod > speedBlinkPeriod / 2;

  /// 일시정지를 걸 수 있는 상태인가 — 끝난 화면에서는 걸 것이 없다
  bool get canPause => !isFinished;

  void pause() {
    if (!canPause) return;
    paused = true;
    pauseElapsed = 0;
  }

  void resume() => paused = false;

  /// 효과가 풀리기 전 예고로 깜빡일 시간(초)
  static const double effectWarnSeconds = 2;

  /// 상단 기호를 지금 켜 둘 것인가 — 만료 2초 전부터 깜빡인다 (2026-09-04).
  ///
  /// 주요 로직 : 속도 표시에만 있던 예고를 버프 전체로 넓힌 것이다.
  ///   무적 6초가 언제 끝나는지 알 수 없어, **끝난 줄 모르고 벽돌에 처박는** 일이 있었다.
  bool effectBlinkOn(ItemType t) {
    final left = effects[t];
    if (left == null || left > effectWarnSeconds) return true;
    return left % speedBlinkPeriod > speedBlinkPeriod / 2;
  }

  /// 떨어지고 있는 아이템들
  List<FallingItem> fallingItems = [];

  /// 스테이지 시작 안내(STAGE n)를 아직 보여줄 때인가.
  /// 스테이지를 깔면 켜지고, 공을 처음 쏘면 꺼진다.
  /// 공을 놓쳐 다시 대기 상태가 되어도 다시 켜지지는 않는다.
  bool stageIntro = true;
  int lives = maxLives;
  int score = 0;

  /// 목숨 개수. 화면에는 하트로 그린다.
  static const int maxLives = 3;

  /// 발사 각도 범위 — 수직 기준 좌우 45도(전체 90도)
  static const double launchSpread = pi / 4;

  /// 패들에 맞았을 때 튕겨 나가는 최대 각도(수직 기준)
  static const double maxBounceAngle = pi / 3;

  /// 멀티공으로 나뉜 공끼리 벌리는 각도 (15도)
  static const double splitSpread = pi / 12;

  // ─── 스테이지 ────────────────────────────────────────────────────

  /// 스테이지 표 — 줄별 내구도(위쪽 줄부터)와 공 속도 단계.
  ///
  /// 주요 로직 : 난이도를 코드가 아니라 이 표 하나로 정한다.
  ///   줄 수·색·내구도·속도가 전부 숫자라, 스테이지를 늘리거나 바꿔도
  ///   충돌·그리기 코드는 건드릴 필요가 없다.
  ///
  /// 상세 설명 : 속도는 speedTable 의 **자리 번호**다.
  ///   1·2 = 1(300) · 3~5 = 2(390) · 6~8 = 3(480) · 9·10 = 4(570) · 11 = 5(670). (2026-09-04 재배치)
  ///   11은 10과 벽돌 구성이 같고 속도만 올라간다 — 같은 판을 더 빠르게 푸는 단계.
  ///
  /// 클리어 총점 = 각 줄의 내구도 합 × 7칸. 점수는 맞을 때마다 1점이므로
  /// 빨강 한 개가 3점이 되어 표의 총점과 저절로 맞는다.
  /// ⚠️ 아이템 개수는 2026-09-04 에 **1.5배**로 올렸다 (반올림).
  ///   예전 값 = 3/2 · 3/2 · 4/3 · 4/3 · 5/5 · 5/5 · 6/6 · 6/6 · 7/8 · 7/8 · 8/10
  static const List<StageSpec> stages = [
    //          줄 구성            속도  도움  방해
    StageSpec([1, 1, 1], 1, 5, 3), //  1  ◇  300
    StageSpec([1, 2, 1], 1, 5, 3), //  2  ◇  300
    StageSpec([1, 3, 1], 2, 6, 5), //  3  ▲  390
    StageSpec([1, 1, 1, 1, 1], 2, 6, 5), //  4  ▲  390
    StageSpec([1, 1, 2, 1, 1], 2, 8, 8), //  5  ▲  390
    StageSpec([1, 1, 3, 1, 1], 3, 8, 8), //  6  ▲2 480
    StageSpec([1, 2, 2, 2, 1], 3, 9, 9), //  7  ▲2 480
    StageSpec([1, 2, 3, 2, 1], 3, 9, 9), //  8  ▲2 480
    StageSpec([1, 3, 2, 3, 1], 4, 11, 12), //  9  ▲3 570
    StageSpec([3, 2, 1, 2, 3], 4, 11, 12), // 10  ▲3 570
    StageSpec([3, 2, 1, 2, 3], 5, 12, 15), // 11  ▲4 670  10과 같은 구성 · 속도만 상승
  ];

  /// 공 속도 단계표 — **초당 픽셀 실제값** (2026-09-03 변경).
  ///
  /// 상세 설명 : 예전에는 「기준 300 × 배수(%)」였는데, 값이 83.3·130 처럼 지저분해져
  ///   실제 속도를 그대로 적는 방식으로 바꿨다. 단계 간 증가율은 대략
  ///   ×1.2 → ×1.3 → ×1.23 → ×1.19 로, 딱 떨어지지 않는 자리는 보기 좋게 다듬은 값이다.
  ///
  /// 주요 로직 : 아이템은 이 표 **안에서 한 단계씩** 움직인다(예전엔 스테이지 기준 ±1).
  ///   최고·최저에 닿으면 더 안 움직이고 지속 시간만 다시 찬다.
  /// 벽돌의 최대 내구도. **색 개수와 같아야 한다** (테스트가 지킨다).
  ///
  /// 주요 로직 : 예전에는 이 값이 어디에도 적혀 있지 않고
  ///   `(hp - 1) / 2` 의 **2 안에 숨어** 있었다. 내구도 4짜리 벽돌이 생기면
  ///   오류 없이 가중치만 조용히 틀어진다 — 가장 찾기 어려운 형태의 고장이다.
  static const int maxBrickHp = 3;

  static const List<int> speedTable = [250, 300, 390, 480, 570, 670, 780];

  /// 속도 단계를 나타내는 기호 — 상단에 `SPEED ▲2` 처럼 상시 표시한다.
  ///
  /// 주요 로직 : 단계가 7개로 늘면서 표기를 바꿨다 (2026-09-04).
  ///   ▲▲▲▲ 식으로 쌓으면 길고 지저분해서 몇 개인지 세어야 알 수 있다.
  ///   기본값은 `○` 이었는데 **공처럼 보여 뜻이 전달되지 않아** `◇` 로 바꿨다.
  static const List<String> speedMarks = [
    '▼', // 0  250  최저
    '◇', // 1  300  기본
    '▲', // 2  390
    '▲2', // 3  480
    '▲3', // 4  570
    '▲4', // 5  670
    '▲5', // 6  780  최고
  ];

  String get speedMark => speedMarks[speedStage];

  /// 속도 효과가 곧 풀리는가 — 이 시간부터 표시를 깜빡여 미리 알린다.
  ///
  /// 주요 로직 : 속도가 예고 없이 원래대로 돌아오면 그 순간 조작이 어긋난다.
  ///   되돌아올 것을 미리 알아야 공을 받을 준비를 할 수 있다 (2026-09-03).
  static const double speedWarnSeconds = 2;

  /// 깜빡임 한 주기(초) — 절반은 켜짐, 절반은 꺼짐
  static const double speedBlinkPeriod = 0.5;

  bool get speedExpiring => speedLeft > 0 && speedLeft <= speedWarnSeconds;

  /// 지금 이 순간 표시를 켜 둘 때인가.
  ///
  /// 주요 로직 : 깜빡이는 상황이 두 가지고, 둘 다 **같은 모습**으로 낸다 (2026-09-03).
  ///   ① 아이템으로 단계가 바뀐 직후 — 바뀐 값을 띄운 채 두 번 (speedFlashSeconds)
  ///   ② 원래 속도로 돌아가기 2초 전 — 되돌아올 것을 미리 알림
  ///   색을 바꾸는 강조는 뺐다. 게임 화면에서 색까지 변하면 시선을 너무 끈다.
  bool get speedBlinkOn {
    if (speedFlash > 0) {
      return speedFlash % speedBlinkPeriod > speedBlinkPeriod / 2;
    }
    if (speedExpiring) {
      return speedLeft % speedBlinkPeriod > speedBlinkPeriod / 2;
    }
    return true;
  }

  bool hasEffect(ItemType t) => effects.containsKey(t);

  /// 패들이 경기장을 벗어나지 않게 위치를 다시 가둔다.
  ///
  /// 2026-09-02 수정 — 아이템을 먹으면 패들이 오른쪽으로 튀어 나가던 문제.
  ///   원인 : 패들 폭은 효과에 따라 바뀌는데(확대 ×2) **중심 위치는 그대로**여서,
  ///          오른쪽 끝에 있던 패들이 넓어지면서 화면 밖으로 삐져나왔다.
  ///          움직이기 전까지 다시 가두는 곳이 없었다.
  ///   대책 : 폭이 바뀌는 모든 지점(획득·해제·시간 만료·화면 크기 변경)에서 다시 가둔다.
  void _clampPaddle() {
    final half = paddleWidth / 2;
    paddleX = paddleX.clamp(half, fieldSize.width - half);
  }

  /// 아이템을 먹었을 때.
  ///
  /// 주요 로직 : 속도와 패들이 서로 다른 규칙을 쓴다 (2026-09-03).
  ///   속도 — 표 안에서 **한 칸씩 누적**. 감속 상태에서 증속을 먹으면 한 칸 올라갈 뿐이다
  ///   패들 — **상쇄**. 반대쪽을 먹으면 둘 다 사라지고 원래 폭으로 (단계가 둘뿐이라 이게 자연스럽다)
  void applyItem(ItemType t) {
    // 먹은 순간을 화면 가운데로 알린다 — **전 종류** (2026-09-03 확대).
    //   예전에는 시간형(무적공·반전·속도)을 뺐다. 상단이나 SPEED 표시에
    //   어차피 남는다는 이유였는데, 두 가지가 걸렸다.
    //   ① 끝단(▼ / ▲▲▲)에서 같은 속도 아이템을 또 먹으면 단계가 안 바뀌어
    //      깜빡임조차 없었다 — 먹었는지 알 길이 없었다
    //   ② 이 표시는 「지금 무엇이 걸렸는가」가 아니라 **「무엇을 먹었는가」**다.
    //      상쇄로 끝나는 경우(축소 걸린 상태에서 확대)에도 띄우는 것과 같은 이유로,
    //      상단에 남는지 여부로 예외를 둘 근거가 없다.
    _startItemFlash(t);
    _emit(t.isHelp ? GameEventType.itemHelp : GameEventType.itemHarm);

    if (t == ItemType.slowBall) return _shiftSpeed(-1, t);
    if (t == ItemType.fastBall) return _shiftSpeed(1, t);

    final opposite = t.opposite;
    if (opposite != null && effects.containsKey(opposite)) {
      effects.remove(opposite);
      _clampPaddle();
      return;
    }

    switch (t.duration) {
      case ItemDuration.instant:
        _applyInstant(t);
      case ItemDuration.timed:
        effects[t] = t.seconds; // 같은 것을 또 먹으면 시간이 다시 찬다
      case ItemDuration.untilLost:
        // 멀티공은 예외 — 이미 걸려 있어도 공 수를 다시 3개로 채운다.
        // 공을 하나둘 잃은 뒤 다시 먹었는데 아무 일도 안 일어나면 먹을 이유가 없다.
        if (t == ItemType.multiBall) {
          effects[t] = double.infinity;
          _refillBalls();
          break;
        }
        if (effects.containsKey(t)) return; // 이미 걸려 있으면 변화 없음
        effects[t] = double.infinity;
    }
    _clampPaddle();
  }

  void _applyInstant(ItemType t) {
    if (t.isBrickSpawn) _spawnBrickRow(t.spawnHp);
  }

  /// 먹은 아이템을 화면 가운데 잠깐 띄운다 — 모든 스테이지에서.
  ///
  /// 상세 설명 : 샘플에서 먼저 켜 보고 플레이에 방해가 안 되는 것을 확인한 뒤
  ///   실제 스테이지까지 넓혔다 (2026-09-03).
  void _startItemFlash(ItemType t) {
    flashItem = t;
    flashLeft = itemFlashSeconds;
  }

  /// 깨진 벽돌이 있는 줄 중 **가장 아래 줄의 빈 자리**에 새 벽돌을 만든다 (2026-09-04).
  ///
  /// 주요 로직 : 「되살리기(RE)」가 아니라 **「새로 만들기(NEW)」** 다.
  ///   ① 색은 원래 그 줄의 색이 아니라 **먹은 아이템 색**(hp)으로 정한다 —
  ///      원래 무슨 색이었는지는 아무도 기억하지 못하므로, 규칙이 눈에 보이지 않는다.
  ///   ② **살아 있는 벽돌은 건드리지 않는다** — 줄 전체를 덮으면 때려 놓은 진행이
  ///      사라지고, 빨강이 파랑으로 바뀌면 오히려 이득이 되어 버린다.
  ///   ③ **아이템은 넣지 않는다** — 생성 아이템이 든 벽돌을 깨서 또 생성 아이템이
  ///      나오면, 방금 한 놀이를 그대로 다시 하는 느낌이 된다.
  void _spawnBrickRow(int hp) {
    for (var r = _rowHp.length - 1; r >= 0; r--) {
      final row = bricks.where((b) => b.row == r).toList();
      if (row.every((b) => b.alive)) continue;
      for (final b in row) {
        if (b.alive) continue;
        b.hp = hp;
        b.item = null;
      }
      return;
    }
  }

  /// 이 스테이지에 나올 수 있는 벽돌 생성 아이템 색 (2026-09-04).
  ///
  /// 주요 로직 : 속도 구간과 **일부러 어긋나게** 나눴다.
  ///   난이도가 오르는 계단이 스테이지마다 다른 요소로 와야
  ///   「앞이랑 똑같은데」 하는 느낌이 덜하다.
  ///     1~5   파랑
  ///     6~8   파랑 + 노랑
  ///     9~11  파랑 + 노랑 + 빨강
  static List<ItemType> spawnColorsFor(int stage) {
    if (stage <= 5) return const [ItemType.brickSpawnHp1];
    if (stage <= 8) {
      return const [ItemType.brickSpawnHp1, ItemType.brickSpawnHp2];
    }
    return const [
      ItemType.brickSpawnHp1,
      ItemType.brickSpawnHp2,
      ItemType.brickSpawnHp3,
    ];
  }

  /// 걸려 있는 효과를 전부 지운다. 공을 놓치거나 스테이지가 바뀔 때.
  void clearEffects() {
    effects.clear();
    fallingItems = [];
    flashItem = null;
    flashLeft = 0;
    _resetSpeed();
    _clampPaddle();
  }

  /// 게임이 끝난 상태인가 (클리어 또는 게임오버).
  ///
  /// 주요 로직 : 끝나면 패들·공을 화면에서 지우고 조작도 받지 않는다.
  ///   남겨 두면 "아직 조작되나?" 하고 만지게 되고, 안내 문구보다 눈이 그쪽으로 간다.
  ///   벽돌은 그대로 두어 결과(얼마나 남았는지)가 보이게 한다.
  bool get isFinished =>
      status == GameStatus.cleared || status == GameStatus.gameOver;

  /// 아이템 시험용 샘플 스테이지인가 (치트로만 들어간다).
  ///
  /// 상세 설명 : 실제 스테이지 번호(1~11)와 섞이지 않도록 0번을 쓴다.
  ///   파랑 5줄(35칸)이고, 여기서 아이템을 시험한 뒤 실제 스테이지에 적용한다.
  bool get isSampleStage => stage == sampleStage;

  static const int sampleStage = 0;

  /// 샘플 스테이지 구성 — 파랑 5줄(35칸) · 아이템 시험용
  static const StageSpec sampleSpec = StageSpec([1, 1, 1, 1, 1], 1, 0, 0);

  /// 샘플에 심는 아이템 개수 — 종류마다 이만큼씩
  ///
  /// 상세 설명 : 속도 시험이 끝나 **전 종류를 조금씩** 넣는 방식으로 돌렸다
  ///   (2026-09-03). 한 종류를 여러 번 먹어 봐야 중복·상쇄 규칙이 드러난다.
  static const int sampleItemsEach = 2;

  /// 샘플에서 빼는 아이템 — 벽돌을 한 번에 쓸어버려 다른 시험을 할 시간이 없다
  static const Set<ItemType> sampleExcluded = {ItemType.invincibleBall};

  /// 샘플 스테이지 — **줄마다 심을 아이템을 지정**한다 (2026-09-10).
  ///
  /// ⭐ 주요 로직 : 무작위로 흩뿌리면 **먹는 순서를 정할 수 없다.**
  ///   「무엇을 먼저 먹었는가」로 갈리는 증상을 쫓을 때는 순서가 곧 시험 조건이다.
  ///   벽돌은 **아래 줄부터** 깨지므로 **먼저 먹이고 싶은 것을 큰 번호 줄에** 둔다
  ///   (row 0 = 맨 위 · row 4 = 맨 아래). 예) `{4: ItemType.slowBall, 3: ItemType.paddleGrow}`
  ///   한 줄 전체(7칸)가 같은 아이템이라 **반복 습득**도 함께 볼 수 있다.
  ///
  /// ⚠️ **평소에는 비워 둔다** — 비어 있으면 전 종류를 조금씩 흩뿌린다.
  ///   첫 습득 끊김 시험(2026-09-10)에 썼고, 시험이 끝나 비웠다 (2026-09-11).
  static const Map<int, ItemType> sampleRowItem = {};

  /// 마지막 스테이지인가 (다음 스테이지가 아직 없는가)
  bool get isLastStage => stage >= stages.length;

  StageSpec get spec => isSampleStage
      ? sampleSpec
      : stages[(stage - 1).clamp(0, stages.length - 1)];

  List<int> get _rowHp => spec.rowHp;

  /// 공 속력(초당 픽셀) — **경기장 폭에 비례**한다 (2026-09-07 수정).
  ///
  /// 주요 로직 : 속도만 고정 픽셀로 두면 크기를 비례시킨 의미가 없어진다.
  ///   화면이 커지면 건너야 할 거리는 늘어나는데 속력은 그대로라 **느려진 것처럼** 느껴지고,
  ///   작은 폰에서는 반대로 빨라진다. **기기가 난이도를 바꾸는** 마지막 구멍이었다.
  ///   `speedTable` 의 값은 이제 **기준 폭에서의 px/s** 로 읽는다.
  double get ballSpeed => speedTable[speedStage] * scale;

  /// 이 스테이지가 정한 기본 속도 단계
  int get baseSpeedStage => spec.speedLevel;

  /// 속도 단계를 아이템으로 한 칸 움직인다. 표 밖으로는 안 나간다.
  ///
  /// 주요 로직 : 끝단에서 같은 아이템을 또 먹어도 **지속 시간은 다시 찬다**.
  ///   「먹으면 시간이 리셋된다」는 규칙을 단계와 무관하게 지키기 위해서다.
  void _shiftSpeed(int delta, ItemType t) {
    final next = (speedStage + delta).clamp(0, speedTable.length - 1);
    if (next != speedStage) {
      speedStage = next;
      speedFlash = speedFlashSeconds;
      _resyncBallSpeed();
    }
    speedLeft = t.seconds;
  }

  /// 속도 단계를 스테이지 기본값으로 되돌린다 (시간 만료 · 공 놓침 · 스테이지 전환).
  ///
  /// 주요 로직 : 여기서는 **깜빡이지 않는다** (2026-09-03).
  ///   만료는 이미 2초 전부터 예고했고, 스테이지 시작은 숫자만 조용히 바뀌면 된다.
  ///   깜빡임은 「내가 방금 아이템을 먹어서 바뀌었다」는 뜻으로만 쓴다.
  void _resetSpeed() {
    speedLeft = 0;
    speedFlash = 0;
    if (speedStage == baseSpeedStage) return;
    speedStage = baseSpeedStage;
    _resyncBallSpeed();
  }

  /// 속도 효과 시간과 강조 표시 시간을 줄인다.
  ///
  /// 주요 로직 : 시간이 다 되면 **몇 칸을 움직였든 한 번에** 기본 단계로 돌아간다.
  ///   한 칸씩 되돌리면 「먹을 때마다 시간이 다시 찬다」는 규칙과 어긋나
  ///   언제 원래대로 돌아오는지 예측할 수 없어진다.
  void _tickSpeed(double dt) {
    if (speedFlash > 0) speedFlash = (speedFlash - dt).clamp(0, double.infinity);
    if (speedLeft <= 0) return;
    speedLeft -= dt;
    if (speedLeft <= 0) _resetSpeed();
  }

  /// 날아가던 공들의 속력만 새 단계에 맞춘다 (방향은 그대로).
  void _resyncBallSpeed() {
    for (final b in balls) {
      final d = b.velocity.distance;
      if (d == 0) continue;
      b.velocity = b.velocity * (ballSpeed / d);
    }
  }

  int get brickRows => _rowHp.length;

  /// 스테이지를 깔고 대기 상태로 되돌린다.
  void loadStage(int newStage) {
    stage = newStage;
    bricks = [
      for (var r = 0; r < _rowHp.length; r++)
        for (var c = 0; c < brickCols; c++) Brick(r, c, _rowHp[r]),
    ];
    _placeItems();
    clearEffects(); // 스테이지가 바뀌면 아이템 효과는 전부 초기화
    paused = false; // 일시정지를 걸어 둔 채 스테이지가 넘어가는 일이 없게
    status = GameStatus.ready;
    stageIntro = true;
    _placeBallOnPaddle();
  }

  /// 스테이지 표에 정한 개수만큼 아이템을 벽돌에 심는다.
  ///
  /// 주요 로직 : 어느 벽돌에 들어갈지는 무작위지만 치우침을 준다.
  ///   스테이지가 올라갈수록 도움은 단단한 벽돌(노랑·빨강)에,
  ///   방해는 무른 벽돌(파랑)에 잘 붙는다 — 도움은 얻기 어렵고 방해는 자주 나오게.
  void _placeItems() {
    if (isSampleStage) {
      _placeSampleItems();
      return;
    }

    final progress = stages.length > 1
        ? (stage.clamp(1, stages.length) - 1) / (stages.length - 1)
        : 0.0;

    final help = ItemType.values.where((t) => t.isHelp).toList();
    // 생성 계열은 **한 슬롯으로 묶어** 뽑는다 (2026-09-04).
    //   색이 3종이라고 뽑힐 확률까지 3배가 되면 방해 아이템이 생성 일색이 된다.
    //   슬롯이 뽑히면 그때 스테이지가 허용하는 색 중에서 고른다.
    final harm = [
      ...ItemType.values.where((t) => !t.isHelp && !t.isBrickSpawn),
      ItemType.brickSpawnHp1, // 생성 대표 슬롯
    ];
    final spawnColors = spawnColorsFor(stage);
    final free = [...bricks];

    void place(int count, List<ItemType> pool, bool wantTough) {
      for (var i = 0; i < count && free.isNotEmpty; i++) {
        final weights = free.map((b) {
          // 0(가장 무른 벽돌) ~ 1(가장 단단한 벽돌)
          final tough = (b.hp - 1) / (maxBrickHp - 1);
          final bias = wantTough ? tough : 1 - tough;
          return 1 + progress * bias * 3;
        }).toList();
        final total = weights.fold<double>(0, (a, b) => a + b);
        var pick = _random.nextDouble() * total;
        var idx = 0;
        for (; idx < weights.length - 1; idx++) {
          pick -= weights[idx];
          if (pick <= 0) break;
        }
        final target = free.removeAt(idx);
        var type = pool[_random.nextInt(pool.length)];
        if (type.isBrickSpawn) {
          type = spawnColors[_random.nextInt(spawnColors.length)];
        }
        final replaced = Brick(target.row, target.col, target.hp, item: type);
        bricks[bricks.indexOf(target)] = replaced;
      }
    }

    place(spec.helpItems, help, true);
    place(spec.harmItems, harm, false);
  }

  /// 샘플 스테이지 — 무적공을 뺀 전 종류를 두 개씩 무작위로 심는다 (2026-09-03).
  ///
  /// 주요 로직 : 종류마다 같은 개수를 넣는다. 무작위로 뿌리면 어떤 아이템은
  ///   한 번도 안 나와 시험이 안 되기 때문이다. 위치만 무작위다.
  void _placeSampleItems() {
    // 줄 지정이 있으면 그대로 심고 끝낸다 — 위 [sampleRowItem] 설명 참조
    if (sampleRowItem.isNotEmpty) {
      for (var i = 0; i < bricks.length; i++) {
        final b = bricks[i];
        final type = sampleRowItem[b.row];
        if (type != null) bricks[i] = Brick(b.row, b.col, b.hp, item: type);
      }
      return;
    }

    final free = [...bricks];
    for (final type in ItemType.values) {
      if (sampleExcluded.contains(type)) continue;
      for (var i = 0; i < sampleItemsEach && free.isNotEmpty; i++) {
        final target = free.removeAt(_random.nextInt(free.length));
        bricks[bricks.indexOf(target)] =
            Brick(target.row, target.col, target.hp, item: type);
      }
    }
  }

  /// 처음부터 다시 시작.
  /// 샘플 스테이지에서 눌렀으면 샘플을 다시 깐다 — 시험 중에 실제 판으로 튕겨 나가지 않게.
  void restart() {
    final backToSample = isSampleStage;
    lives = maxLives;
    score = 0;
    loadStage(backToSample ? sampleStage : 1);
  }

  int get remainingBricks => bricks.where((b) => b.alive).length;

  /// 격자 위치를 현재 경기장 크기 기준 사각형으로 바꾼다.
  Rect brickRect(Brick b) {
    final usable = fieldSize.width - brickSideMargin * 2;
    final cellW = (usable - brickGap * (brickCols - 1)) / brickCols;
    final left = brickSideMargin + b.col * (cellW + brickGap);
    final top = brickTopMargin + b.row * (brickHeight + brickGap);
    return Rect.fromLTWH(left, top, cellW, brickHeight);
  }

  // ─── 패들 · 공 발사 ──────────────────────────────────────────────

  /// 패들 윗면의 y 좌표 — 충돌 판정 기준선
  double get paddleTop => fieldSize.height - paddleBottomMargin - paddleHeight;

  Rect get paddleRect => Rect.fromLTWH(
        paddleX - paddleWidth / 2,
        paddleTop,
        paddleWidth,
        paddleHeight,
      );

  /// 마지막으로 들어온 입력 x — 좌우 반전에서 움직인 거리를 재는 데 쓴다
  double? _lastInputX;

  /// 패들을 x 로 옮긴다. 경기장 밖으로는 나가지 않는다.
  /// 대기 중이면 공도 패들을 따라온다.
  void movePaddleTo(double x) {
    if (isFinished) return; // 끝난 뒤에는 조작을 받지 않는다

    // 좌우 반전 아이템
    //
    // 2026-09-02 수정 — 반전이 걸리면 패들이 반대편으로 순간 이동하던 문제.
    //   원인 : 좌표를 화면 가운데 기준으로 그대로 뒤집었다(x → 폭 - x).
    //          마우스가 왼쪽에 있으면 효과가 걸리는 순간 패들이 오른쪽 끝으로 날아간다.
    //   대책 : 위치가 아니라 **움직인 거리**를 뒤집는다.
    //          손을 오른쪽으로 옮기면 패들은 그만큼 왼쪽으로 간다.
    //          조작은 확실히 반대가 되면서 순간 이동은 없다.
    double wanted;
    if (hasEffect(ItemType.reverse) && _lastInputX != null) {
      wanted = paddleX - (x - _lastInputX!);
    } else {
      wanted = x;
    }
    _lastInputX = x;

    final half = paddleWidth / 2;
    paddleX = wanted.clamp(half, fieldSize.width - half);
    if (status == GameStatus.ready) _placeBallOnPaddle();
  }

  /// 멀티공을 먹었을 때 공을 3개로 채운다.
  ///
  /// 주요 로직 : 지금 살아 있는 공 수에 따라 나누는 방식이 다르다.
  ///   1개 — 그 공을 좌우로 벌려 3개로 나눈다
  ///   2개 — **가장 높이 있는 공**을 가던 방향 중심으로 양쪽으로 가른다.
  ///        위에 있는 공이 살아남을 시간이 길어 나누는 값어치가 크다.
  ///   3개 이상 — 그대로 둔다
  void _refillBalls() {
    if (balls.length >= 3) return;
    if (balls.length <= 1) {
      splitBalls(3);
      return;
    }

    final src = balls.reduce((a, b) => a.pos.dy <= b.pos.dy ? a : b);
    final speed = src.velocity.distance;
    if (speed == 0) {
      splitBalls(3);
      return;
    }
    const spread = splitSpread;
    final base = atan2(src.velocity.dx, -src.velocity.dy);
    src.velocity =
        Offset(sin(base - spread) * speed, -cos(base - spread) * speed);
    balls.add(Ball(
      pos: src.pos,
      velocity: Offset(sin(base + spread) * speed, -cos(base + spread) * speed),
    ));
  }

  /// 공을 여러 개로 나눈다 — 멀티볼 아이템용.
  ///
  /// 주요 로직 : 지금 있는 공마다 좌우로 각도를 벌린 사본을 만든다.
  ///   속도 크기는 그대로 두어야 갑자기 빨라지거나 느려지지 않는다.
  ///
  /// 2026-09-03 수정 — 좌우가 대칭이 아니었다.
  ///   원인 : 벌리는 각을 `±15도 × 순번` 으로 잡아 두 번째 공이 **-30도**로 갔다.
  ///          공 3개가 원본 · +15 · -30 이 되어 한쪽으로 치우친 부채꼴이 나온다.
  ///   대책 : 순번을 좌우 한 쌍씩 세어 +15 · -15 · +30 · -30 … 으로 벌린다.
  void splitBalls(int total) {
    if (balls.isEmpty || total <= balls.length) return;
    final added = <Ball>[];
    var i = 1;
    while (balls.length + added.length < total) {
      final src = balls[(i - 1) % balls.length];
      final speed = src.velocity.distance;
      final base = atan2(src.velocity.dx, -src.velocity.dy);
      final step = ((i + 1) ~/ 2) * splitSpread; // 1,1,2,2,3,3 … 번째 칸
      final angle = base + (i.isOdd ? step : -step);
      added.add(Ball(
        pos: src.pos,
        velocity: Offset(sin(angle) * speed, -cos(angle) * speed),
      ));
      i++;
    }
    balls = [...balls, ...added];
  }

  /// 공을 하나로 되돌려 패들 위에 얹는다. 멀티볼도 여기서 정리된다.
  void _placeBallOnPaddle() {
    balls = [
      Ball(pos: Offset(paddleX, paddleTop - ballRadius), velocity: Offset.zero),
    ];
  }

  /// 공을 쏘아 올린다. 터치 또는 스페이스로 호출된다.
  ///
  /// 주요 로직 : 발사 각도를 수직 기준 좌우 45도 안에서 무작위로 잡는다.
  ///   늘 같은 각도로 나가면 첫 몇 초가 매번 똑같아져 지루하고,
  ///   범위를 더 넓히면 거의 옆으로 날아가 벽만 오래 때린다.
  void launch() {
    if (status != GameStatus.ready) return;
    final angle = (_random.nextDouble() * 2 - 1) * launchSpread;
    for (final b in balls) {
      b.velocity = Offset(sin(angle) * ballSpeed, -cos(angle) * ballSpeed);
    }
    status = GameStatus.playing;
    stageIntro = false;
    _emit(GameEventType.launch);
  }

  /// 화면 크기가 바뀌면 공과 패들을 경기장 안으로 다시 넣는다.
  void resize(Size size) {
    fieldSize = size;
    // 크기가 바뀌면 배율이 바뀌므로 날아가던 공의 속력도 다시 맞춘다.
    // 안 맞추면 창을 키운 순간 그 공만 예전 속력으로 남아 느리게 보인다.
    _resyncBallSpeed();
    // movePaddleTo 를 쓰면 좌우 반전 효과가 걸린 동안 위치가 뒤집혀 버린다
    _clampPaddle();
    if (status == GameStatus.ready) {
      _placeBallOnPaddle();
    } else {
      for (final b in balls) {
        b.pos = Offset(
          b.pos.dx.clamp(ballRadius, size.width - ballRadius),
          b.pos.dy.clamp(ballRadius, size.height - ballRadius),
        );
      }
    }
  }

  // ─── 매 프레임 계산 ─────────────────────────────────────────────

  /// dt = 직전 프레임으로부터 흐른 시간(초).
  /// 프레임 수가 아니라 시간으로 움직여야 기기 성능에 따라 속도가 달라지지 않는다.
  void update(double dt) {
    // 일시정지 — 게임 시간은 멈추고 깜빡임용 시계만 돈다 (2026-09-04).
    //
    // 주요 로직 : 상태(GameStatus)로 만들지 않고 별도 스위치로 두었다.
    //   일시정지는 「게임이 어디까지 갔는가」가 아니라 **잠깐 멈춤**이라,
    //   상태에 넣으면 풀 때 원래 상태로 되돌리는 코드가 따로 필요해진다.
    if (paused) {
      pauseElapsed += dt;
      return;
    }
    if (status != GameStatus.playing) return;

    _tickEffects(dt);

    for (final ball in balls) {
      _moveBall(ball, dt);
    }

    _moveItems(dt);

    // 바닥으로 빠진 공은 없앤다. 남은 공이 하나도 없을 때만 목숨이 준다.
    balls.removeWhere((b) => b.pos.dy - ballRadius > fieldSize.height);
    if (balls.isEmpty) {
      _loseBall();
      return;
    }

    if (remainingBricks == 0) {
      completeStage();
    }
  }

  /// 시간형 효과의 남은 시간을 줄이고, 다 된 것은 지운다.
  void _tickEffects(double dt) {
    _tickSpeed(dt);
    if (flashLeft > 0) {
      flashLeft -= dt;
      if (flashLeft <= 0) {
        flashLeft = 0;
        flashItem = null;
      }
    }
    if (effects.isEmpty) return;
    final done = <ItemType>[];
    for (final e in effects.entries) {
      if (e.value.isInfinite) continue;
      final left = e.value - dt;
      if (left <= 0) {
        done.add(e.key);
      } else {
        effects[e.key] = left;
      }
    }
    if (done.isEmpty) return;
    for (final t in done) {
      effects.remove(t);
    }
    _clampPaddle(); // 패들 크기 효과가 풀렸을 수 있다
  }

  /// 아이템을 아래로 내리고, 패들에 닿은 것은 효과를 적용한다.
  void _moveItems(double dt) {
    if (fallingItems.isEmpty) return;
    final caught = <FallingItem>[];
    for (final it in fallingItems) {
      // 낙하 속도도 폭에 비례시킨다 — 안 그러면 큰 화면에서만 아이템이 느리게 떨어진다
      it.pos = Offset(it.pos.dx, it.pos.dy + it.speed * scale * dt);
      if (_circleHitsRect(it.pos, paddleRect, itemRadius)) {
        caught.add(it);
      }
    }
    for (final it in caught) {
      applyItem(it.type);
    }
    fallingItems.removeWhere(
      (it) => caught.contains(it) || it.pos.dy - itemRadius > fieldSize.height,
    );
  }

  /// 공 하나를 한 프레임 움직이고 부딪힌 것을 처리한다.
  void _moveBall(Ball ball, double dt) {
    final from = ball.pos;
    var next = from + ball.velocity * dt;
    var v = ball.velocity;
    final r0 = ballRadius;

    // 1 좌우 벽 — 벽을 넘어간 만큼 **되꺾어서** 진행 방향을 뒤집는다
    //
    // 2026-09-03 수정 — 부딪힌 프레임만 이동거리가 짧아 잠깐 멈췄다 튀는 느낌이 났다.
    //   원인 : 벽에 딱 붙여 놓기만 하고(next = r0) 넘어간 거리를 버렸다.
    //          그 프레임만 3px, 다음 프레임부터 5px 를 가니 눈에는 「멈칫 → 가속」으로 보인다.
    //   대책 : 넘어간 만큼을 반사 방향으로 **마저 보낸다**(거울처럼 접기).
    //          이러면 프레임마다 가는 거리가 일정해진다.
    //
    // 2026-09-04 : 같은 식이 위 벽·벽돌에도 그대로 있어 reflectJustCrossedFace 로 모았다.
    //   프레임 시작(from) x 는 이 함수 맨 끝에서 항상 경기장 안으로 가둬 두므로
    //   여기 오는 공은 「이번 프레임에 막 넘어선」 경우뿐이다 — 되꺾기 전제가 성립한다.
    if (next.dx - r0 < 0) {
      next = Offset(
        reflectJustCrossedFace(from: from.dx, to: next.dx, face: r0),
        next.dy,
      );
      v = Offset(v.dx.abs(), v.dy);
      _emit(GameEventType.wallHit);
    } else if (next.dx + r0 > fieldSize.width) {
      final limit = fieldSize.width - r0;
      next = Offset(
        reflectJustCrossedFace(from: from.dx, to: next.dx, face: limit),
        next.dy,
      );
      v = Offset(-v.dx.abs(), v.dy);
      _emit(GameEventType.wallHit);
    }

    // 2 위 벽
    if (next.dy - r0 < 0) {
      next = Offset(
        next.dx,
        reflectJustCrossedFace(from: from.dy, to: next.dy, face: r0),
      );
      v = Offset(v.dx, v.dy.abs());
      _emit(GameEventType.wallHit);
    }

    // 3 벽돌 — 공 하나가 한 프레임에 하나만 맞힌다.
    //   여러 개가 동시에 맞으면 어느 면에서 맞았는지가 흐려져 반사 방향이 튄다.
    for (final b in bricks) {
      if (!b.alive) continue;
      final r = brickRect(b);
      if (!_circleHitsRect(next, r, r0)) continue;

      final hpBefore = b.hp;
      b.hp--;
      score++;
      _emit(b.alive ? GameEventType.brickHit : GameEventType.brickBroken,
          hp: hpBefore);
      if (!b.alive && b.item != null) {
        fallingItems.add(FallingItem(type: b.item!, pos: r.center));
      }

      // 무적공 — 반사하지 않고 그대로 뚫고 지나간다.
      // 한 프레임에 하나만 부수는 제한도 풀어야 지나간 자리가 전부 사라진다.
      if (hasEffect(ItemType.invincibleBall)) continue;

      // 어느 면으로 들어왔는지 정해 그 축만 뒤집는다.
      //
      // 2026-09-02 수정 — 벽에 붙어 올라가면 벽돌 한 줄을 뚫고 지나가던 문제.
      //   원인 : 반사축을 "직전 x 가 벽돌의 좌우 바깥이었는가"로만 판단했다.
      //          공이 왼쪽 벽에 붙으면(x=8, 벽돌 왼쪽 끝=12) 항상 '바깥'으로 잡혀
      //          매 프레임 x 만 뒤집혔고, 위로 가는 속도는 그대로라
      //          한 프레임에 한 칸씩 부수며 그대로 올라갔다.
      //   대책 ① 직전 위치가 그 면의 '완전히 바깥'이었는지로 본다
      //        ② 속도가 그 면을 향하고 있을 때만 그 축을 뒤집는다
      //        ③ 뒤집은 뒤 벽돌 밖으로 내보내 다음 프레임에 다시 겹치지 않게 한다
      //          (내보내는 방식은 2026-09-03 에 「되꺾기」로 바뀌었다 — 아래 참조)
      final wasLeft = from.dx + r0 <= r.left;
      final wasRight = from.dx - r0 >= r.right;
      final wasAbove = from.dy + r0 <= r.top;
      final wasBelow = from.dy - r0 >= r.bottom;

      final hitSide = (wasLeft && v.dx > 0) || (wasRight && v.dx < 0);
      final hitFace = (wasAbove && v.dy > 0) || (wasBelow && v.dy < 0);

      final overlapX = (r0 + r.width / 2) - (next.dx - r.center.dx).abs();
      final overlapY = (r0 + r.height / 2) - (next.dy - r.center.dy).abs();

      // 이미 겹친 채로 시작한 경우 — 위아래로 처리하되 **되꺾지 않는다** (2026-09-04 수정).
      //
      //   증상 : 벽돌과 벽돌 사이 틈에 낀 공이 충돌 뒤 **벽돌 위로 순간이동**했다.
      //   원인 : 되꺾기는 「면을 거울처럼 접는」 계산이라, 공이 면에서 깊이 들어와 있을수록
      //          반대편으로 **그만큼 멀리** 튄다. 틈에 낀 상태는 이미 깊이 들어와 있다.
      //   대책 : 이 경우만 **면에 붙여** 놓고 축을 뒤집는다. 그 프레임에 못 간 거리는
      //          아주 짧아, 순간이동보다 훨씬 눈에 덜 띈다.
      //   ⚠️ 축을 「덜 파고든 쪽」으로 고르면 **벽 붙어 상승 문제가 되살아난다**
      //      (2026-09-02 에 잡았던 것). 이 경우는 예전처럼 **언제나 위아래**로 푼다.
      if (!hitSide && !hitFace) {
        final face = v.dy > 0 ? r.top - r0 : r.bottom + r0;
        next = Offset(next.dx, face);
        v = Offset(v.dx, -v.dy);
        break;
      }

      var reflectX = hitSide;
      if (hitSide && hitFace) {
        // 모서리로 들어온 경우 — 덜 파고든 축으로 튕긴다
        reflectX = overlapX < overlapY;
      }

      // 2026-09-03 : 벽과 같은 이유로 **파고든 만큼 되꺾어** 준다.
      //   면에 붙여 놓기만 하면 그 프레임만 덜 가서 「멈칫 → 가속」으로 보인다.
      //
      // 2026-09-04 : 벽과 똑같은 식이라 reflectJustCrossedFace 로 모았다.
      //   여기까지 온 것은 hitSide 나 hitFace 가 참인 경우뿐이고, 그 둘은 각각
      //   「직전 위치가 그 면의 완전히 바깥」이었음을 뜻한다 — 즉 이번 프레임에 막 넘어섰다.
      //   이미 겹친 채 시작한 경우는 위 분기에서 이미 빠져나갔으므로 전제가 성립한다.
      if (reflectX) {
        final face = v.dx > 0 ? r.left - r0 : r.right + r0;
        next = Offset(
          reflectJustCrossedFace(from: from.dx, to: next.dx, face: face),
          next.dy,
        );
        v = Offset(-v.dx, v.dy);
      } else {
        final face = v.dy > 0 ? r.top - r0 : r.bottom + r0;
        next = Offset(
          next.dx,
          reflectJustCrossedFace(from: from.dy, to: next.dy, face: face),
        );
        v = Offset(v.dx, -v.dy);
      }
      break;
    }

    // 4 패들 — 여기도 파고든 만큼을 새 방향으로 마저 보낸다 (2026-09-03).
    //   패들은 맞은 지점에 따라 방향이 아예 달라지므로 축을 접는 대신
    //   **남은 거리만큼 새 방향으로** 밀어 준다. 결과는 같고(프레임당 거리 일정) 계산이 단순하다.
    if (v.dy > 0 && _hitsPaddleThisFrame(from, next, r0)) {
      final x = _paddleContactX(from, next, r0);
      final face = paddleTop - r0;
      final left = (next.dy - face).abs();
      v = _bounceOffPaddle(x, v.distance);
      final dir = v / v.distance;
      next = Offset(next.dx, face) + dir * left;
      _emit(GameEventType.paddleHit);
    }

    // 되꺾는 과정에서 경기장을 벗어날 수 있어 마지막에 한 번 가둔다
    ball.pos = Offset(next.dx.clamp(r0, fieldSize.width - r0), next.dy);
    ball.velocity = v;
  }

  /// 스테이지를 다 깼을 때.
  ///
  /// 주요 로직 : 다음 스테이지가 있으면 이어서 진행하고, 마지막이면 CLEARED 로 끝낸다.
  ///   이때 목숨·점수는 건드리지 않는다 — 스테이지가 바뀌어도 한 판은 계속이므로.
  void completeStage() {
    // 샘플은 시험용이라 다음 스테이지로 넘어가지 않고 그 자리에서 끝낸다.
    // 실제 진행에 끼어들면 시험 중에 엉뚱한 스테이지로 넘어가 버린다.
    if (isSampleStage || isLastStage) {
      status = GameStatus.cleared;
      return;
    }
    loadStage(stage + 1);
  }

  /// 공을 놓쳤을 때. 목숨이 남았으면 패들 위에서 다시 대기한다.
  void _loseBall() {
    _emit(GameEventType.ballLost);
    clearEffects(); // 새 공으로 시작하면 효과는 전부 사라진다
    lives--;
    if (lives <= 0) {
      lives = 0;
      status = GameStatus.gameOver;
      _placeBallOnPaddle();
      return;
    }
    status = GameStatus.ready;
    _placeBallOnPaddle();
  }

  /// 공(원)이 사각형과 겹치는가 — 사각형에서 공 중심에 가장 가까운 점까지의 거리로 본다
  bool _circleHitsRect(Offset center, Rect r, double radius) {
    final nx = center.dx.clamp(r.left, r.right);
    final ny = center.dy.clamp(r.top, r.bottom);
    final dx = center.dx - nx;
    final dy = center.dy - ny;
    return dx * dx + dy * dy <= radius * radius;
  }

  /// 이번 프레임에 패들에 맞았는가.
  ///
  /// 2026-09-02 수정 — 공이 패들을 그냥 통과해 버리는 문제가 있었다.
  ///   원인 : 공이 빠르면 한 프레임에 패들 두께(12px)보다 훨씬 많이 움직인다.
  ///          프레임 시작엔 패들 위, 끝엔 패들 아래여서 겹친 순간이 아예 없다.
  ///          (게임에서 흔한 터널링 문제)
  ///   대책 1 겹쳤는가가 아니라 패들 윗면을 넘어섰는가로 본다
  ///        2 넘어선 그 순간의 x 로 판정한다 — 프레임 끝 x 로 보면
  ///          대각선으로 빠르게 내려올 때 이미 패들 밖으로 지나가 있다
  ///        3 그래도 못 잡는 경우(패들을 옆에서 공 밑으로 밀어 넣은 경우)를 위해
  ///          마지막에 겹침 판정을 한 번 더 한다
  bool _hitsPaddleThisFrame(Offset from, Offset next, double radius) {
    final a = from.dy + radius;
    final b = next.dy + radius;
    if (a <= paddleTop && b >= paddleTop) {
      return _hitsPaddle(_paddleContactX(from, next, radius), radius);
    }
    return _circleHitsRect(next, paddleRect, radius);
  }

  /// 패들 윗면을 지나는 순간의 공 x 좌표.
  /// 한 프레임에 크게 움직이면 프레임 끝 x 로 보면 어긋나므로 교차 시점으로 되돌린다.
  double _paddleContactX(Offset from, Offset next, double radius) {
    final a = from.dy + radius;
    final b = next.dy + radius;
    final span = b - a;
    if (span <= 0) return next.dx;
    final t = ((paddleTop - a) / span).clamp(0.0, 1.0);
    return from.dx + (next.dx - from.dx) * t;
  }

  /// 공 중심 x 가 패들 범위(공 반지름만큼 여유) 안에 있는가
  bool _hitsPaddle(double x, double radius) {
    final half = paddleWidth / 2;
    return x >= paddleX - half - radius && x <= paddleX + half + radius;
  }

  /// 맞은 지점에 따라 튕기는 방향을 바꾼다.
  ///
  /// 주요 로직 : 거울처럼 y 만 뒤집으면 공이 늘 같은 각도로만 오가서
  ///   플레이어가 할 수 있는 게 공 밑에 패들 갖다 대기뿐이 된다.
  ///   패들의 어디에 맞혔는지로 각도가 달라져야 원하는 벽돌을 노릴 수 있다.
  ///     가운데(0) → 거의 수직 / 가장자리(±1) → 최대 60도
  ///   속도의 크기는 그대로 두고 방향만 바꾼다 — 안 그러면 튕길수록 빨라지거나 느려진다.
  Offset _bounceOffPaddle(double x, double speed) {
    final half = paddleWidth / 2;
    final hit = ((x - paddleX) / half).clamp(-1.0, 1.0);
    final angle = hit * maxBounceAngle;
    return Offset(sin(angle) * speed, -cos(angle) * speed);
  }

  // ─── 치트용 (개발 전용) ─────────────────────────────────────────
  //
  //  상세 설명 : 손으로 한 판을 다 하지 않고도 각 상황을 바로 만들기 위한 통로.
  //    목숨·점수 정합성은 신경 쓰지 않는다. **개발자 패널에서만** 부른다.
  //
  //  주요 로직 : 지우지 않고 남겨 둔다 (2026-09-07). 실서비스 빌드에서는
  //    패널이 통째로 빠져 **부르는 곳이 없어지므로**, 여기서 또 막을 이유가 없다.
  //    규칙 코드에 배포 분기를 섞으면 그쪽이 더 위험하다.

  /// 지정한 스테이지의 시작 단계로 바로 간다.
  void debugGoToStage(int n) => loadStage(n.clamp(1, stages.length));

  /// 아이템 시험용 샘플 스테이지로 간다 — 파랑 5줄.
  void debugLoadSampleStage() => loadStage(sampleStage);

  /// 게임 종료 상황으로 바로 간다.
  void debugGameOver() {
    lives = 0;
    status = GameStatus.gameOver;
  }

  /// 현재 스테이지를 자동으로 클리어한다.
  void debugClearStage() {
    for (final b in bricks) {
      b.hp = 0;
    }
    completeStage();
  }
}
