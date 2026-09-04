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

/// 나열 순서 = 화면 표시 번호(1~8)이자 샘플 스테이지에 심는 순서다.
enum ItemType {
  // ── 도움 (푸른색·초록 계열) ──
  invincibleBall(ItemKind.help, ItemDuration.timed, seconds: 6), // 1 ●
  multiBall(ItemKind.help, ItemDuration.untilLost), //              2 ◎
  slowBall(ItemKind.help, ItemDuration.timed, seconds: 10), //      3 ▼
  paddleGrow(ItemKind.help, ItemDuration.untilLost), //             4 ◀ ▶

  // ── 방해 (경고색 계열) ──
  brickRevive(ItemKind.harm, ItemDuration.instant), //              5 ■ ■
  reverse(ItemKind.harm, ItemDuration.timed, seconds: 4), //        6 ◐
  paddleShrink(ItemKind.harm, ItemDuration.untilLost), //           7 ▶ ◀
  fastBall(ItemKind.harm, ItemDuration.timed, seconds: 10); //      8 ▲

  const ItemType(this.kind, this.duration, {this.seconds = 0});

  final ItemKind kind;
  final ItemDuration duration;

  /// 시간형일 때의 지속 시간(초)
  final double seconds;

  bool get isHelp => kind == ItemKind.help;

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
  double get speed => type.isHelp ? 140 : 110;

  static const double radius = 9;
}
