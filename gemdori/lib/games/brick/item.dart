// ═══════════════════════════════════════════════════════════════════
//  item.dart — 아이템 정의
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 아이템 종류와 성질(갈래·지속 방식·지속 시간)
//  제외 사항 : 효과를 실제로 적용하는 일 (BrickState 가 한다)
//
//  주요 로직 : 지속 방식이 세 가지다.
//    instant   즉발 — 먹는 순간 끝. 효과 목록에 남지 않는다 (벽돌 부활)
//    timed     시간형 — 정해진 시간 뒤 사라진다. 같은 것을 또 먹으면 시간만 리셋
//    untilLost 무기한 — 공을 전부 놓칠 때까지 유지 (패들 크기 · 멀티공)
//
//  주요 로직 : 서로 반대인 아이템은 짝(opposite)으로 묶어 둔다.
//    패들 확대 ↔ 축소, 공속 감소 ↔ 증가.
//
//  주요 로직 : 짝을 처리하는 방법이 둘로 갈린다 (2026-09-03).
//    패들 — **상쇄.** 반대쪽을 먹으면 둘 다 사라지고 원래 폭으로 돌아간다.
//      무기한형이라 「시간을 리셋한다」는 개념 자체가 없고, 확대·축소 둘뿐이라
//      단계식으로 만들 자리가 없다.
//    공속 — **단계식.** 상쇄하지 않고 속도표 안에서 한 칸씩 움직인다.
//      다섯 단계나 되어 상쇄로 묶으면 가운데 칸들을 쓸 수가 없다.
//      실제 처리는 BrickState._shiftSpeed() 가 한다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui';

/// 아이템 갈래 — 화면에서 도움은 원, 방해는 삼각형으로 그린다
enum ItemKind { help, harm }

/// 지속 방식
enum ItemDuration { instant, timed, untilLost }

/// 성질 — **상단 표시줄에 올릴지를 이것 하나로 가른다** (2026-09-04)
///
/// 주요 로직 : 가르는 기준은 「연출이 있느냐」가 아니라
///   **「효과가 화면 구조로 드러나느냐」** 다.
///     공이 3개인 것 · 패들이 넓은 것 = **구조** → 화면이 이미 답을 보여준다
///     공이 붉게 번쩍이는 것          = **연출** → 걸린 줄은 알아도 무엇이 얼마나인지는 모른다
///   그래서 상단에는 **buff 만** 올린다. 좌우 반전처럼 조작해 봐야 아는 것이
///   이 규칙이 필요한 대표 사례다.
///
///   대충 하면 : 화면이 걸린 효과를 전부 뿌리게 되고(예전 코드가 그랬다),
///   규칙이 코드 어디에도 남지 않아 문서와 조용히 어긋난다.
enum ItemClass {
  /// 상태 — 화면만 봐서는 걸린 줄 모른다. **상단에 올린다**
  buff,

  /// 장비 — 착용 결과가 화면에 그대로 보인다. 상단에 안 올린다
  gear,

  /// 소모·즉발 — 남을 것이 없다. 결과는 벽돌로 보인다
  consumable,
}

/// 나열 순서 = 화면 표시 번호(1~10)이자 샘플 스테이지에 심는 순서다.
/// **상단 표시 순서도 이 순서를 따른다** — 먹은 순서로 두면 자리가 뒤바뀐다.
enum ItemType {
  // ── 도움 ── (「도움=푸른·초록 / 방해=경고색」 규칙은 2026-09-04 폐지 — 색은 디자인 영역)
  invincibleBall(ItemKind.help, ItemDuration.timed, ItemClass.buff, seconds: 6), // 1 ◉
  multiBall(ItemKind.help, ItemDuration.untilLost, ItemClass.gear), //              2 ◎
  slowBall(ItemKind.help, ItemDuration.timed, ItemClass.buff, seconds: 10), //      3 ▼
  paddleGrow(ItemKind.help, ItemDuration.untilLost, ItemClass.gear), //             4 ◀ ▶

  // ── 방해 ──
  //   벽돌 생성 3종 — 이름은 **내구도 기준**이다 (2026-09-04).
  //   색은 내구도에서 따라오는 표현일 뿐이라, 이름에 색을 박으면
  //   나중에 색을 바꿨을 때 이름이 거짓말이 된다.
  brickSpawnHp1(ItemKind.harm, ItemDuration.instant, ItemClass.consumable,
      spawnHp: 1), //                                                             5 ■■ 파랑
  brickSpawnHp2(ItemKind.harm, ItemDuration.instant, ItemClass.consumable,
      spawnHp: 2), //                                                             6 ■■ 노랑
  brickSpawnHp3(ItemKind.harm, ItemDuration.instant, ItemClass.consumable,
      spawnHp: 3), //                                                             7 ■■ 빨강
  reverse(ItemKind.harm, ItemDuration.timed, ItemClass.buff, seconds: 4), //        8 ◐
  paddleShrink(ItemKind.harm, ItemDuration.untilLost, ItemClass.gear), //           9 ▶ ◀
  fastBall(ItemKind.harm, ItemDuration.timed, ItemClass.buff, seconds: 10); //     10 ▲

  const ItemType(this.kind, this.duration, this.cls,
      {this.seconds = 0, this.spawnHp = 0});

  final ItemKind kind;
  final ItemDuration duration;

  /// 상단에 올릴지를 가르는 성질
  final ItemClass cls;

  /// 시간형일 때의 지속 시간(초)
  final double seconds;

  /// 벽돌 생성 아이템이면 **생기는 벽돌의 내구도**(1 파랑 / 2 노랑 / 3 빨강). 아니면 0.
  ///
  /// 주요 로직 : 「되살린다(RE)」가 아니라 **「새로 만든다(NEW)」** 다 (2026-09-04).
  ///   원래 그 줄이 무슨 색이었는지는 아무도 기억하지 못한다.
  ///   대신 **먹은 아이템 색이 곧 생기는 벽돌 색**이라, 규칙이 눈에 보인다.
  final int spawnHp;

  bool get isBrickSpawn => spawnHp > 0;

  bool get isHelp => kind == ItemKind.help;

  /// 상단 표시줄 대상인가.
  ///
  /// 상세 설명 : 속도(▼▲)도 buff 지만 `effects` 에 들어가지 않는다.
  ///   `SPEED ▲2` 표시가 절대 단계를 보여주므로 기호보다 정보가 많다.
  bool get isBuff => cls == ItemClass.buff;

  /// 서로 지우는 짝. 없으면 null
  ItemType? get opposite => switch (this) {
        ItemType.paddleGrow => ItemType.paddleShrink,
        ItemType.paddleShrink => ItemType.paddleGrow,
        ItemType.slowBall => ItemType.fastBall,
        ItemType.fastBall => ItemType.slowBall,
        _ => null,
      };
}

/// 벽돌에서 떨어져 내려오는 아이템
class FallingItem {
  FallingItem({required this.type, required this.pos});

  final ItemType type;

  /// 아이템 중심 좌표
  Offset pos;

  /// 낙하 속도(초당 픽셀).
  /// 주요 로직 : 방해 아이템을 더 느리게 떨어뜨린다.
  ///   화면에 오래 남아, 공을 받으러 가다 같이 먹게 되는 상황이 자주 생긴다.
  ///
  /// ⚠️ 이 값은 **기준 폭에서의 속도**다. 실제로는 `BrickState._moveItems` 가
  ///   배율을 곱해 쓴다 — 공 속력과 같은 규칙.
  double get speed => type.isHelp ? 140 : 110;
}

// 크기(반지름)는 여기에 두지 않는다 — `BrickState.itemRadius` 하나뿐이다.
// 예전에 `FallingItem.radius = 9` 가 있었으나 아무도 쓰지 않았고,
// 값만 겹쳐 있어 나중에 한쪽만 고칠 위험이 있었다 (2026-09-07 삭제)
