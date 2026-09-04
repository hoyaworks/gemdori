// ═══════════════════════════════════════════════════════════════════
//  ball.dart — 공 한 개
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 공 하나의 위치와 속도
//  제외 사항 : 충돌 판정 (BrickState 가 한다)
//
//  상세 설명 : 공을 클래스로 뺀 이유는 아이템 「멀티볼」 때문이다.
//    공이 여러 개가 되면 위치·속도를 한 쌍의 값으로 들 수 없다.
//    아이템을 만들기 전에 미리 바꿔 두어야 나중에 전부 다시 손대지 않는다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui';

class Ball {
  Ball({required this.pos, required this.velocity, this.radius = 8});

  Offset pos;

  /// 초당 이동 픽셀
  Offset velocity;

  final double radius;

  Ball copyWith({Offset? pos, Offset? velocity}) => Ball(
        pos: pos ?? this.pos,
        velocity: velocity ?? this.velocity,
        radius: radius,
      );
}
