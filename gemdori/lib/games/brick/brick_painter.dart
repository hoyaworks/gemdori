// ═══════════════════════════════════════════════════════════════════
//  brick_painter.dart — 그리기 전담
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : BrickState 가 계산해 둔 결과를 캔버스에 그린다
//  제외 사항 : 위치 계산 · 충돌 판정 (여기서 조금이라도 계산하면 규칙이 두 군데로 갈라진다)
//
//  주요 로직 : 벽돌 색을 남은 내구도(hp)로 정한다.
//    3 = red / 2 = yellow / 1 = blue.
//    맞을 때마다 색이 red → yellow → blue 로 내려가므로
//    "몇 대 더 때려야 하는지"가 숫자 없이 색만으로 보인다.
//
//  주요 로직 : shouldRepaint 를 항상 true 로 둔다.
//    상태 객체를 새로 만들지 않고 안의 값만 바꾸기 때문에,
//    Flutter 가 같은 객체니까 다시 안 그려도 되겠다고 판단하면 화면이 멈춘다.
//
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/material.dart';

import 'brick_state.dart';
import 'item.dart';

/// 남은 내구도별 벽돌 색
const Map<int, Color> kBrickColors = {
  3: Color(0xFFFF6B6B), // red   — 3번 맞아야 깨짐
  2: Color(0xFFFFD86B), // yellow — 2번
  1: Color(0xFF6FC3FF), // blue  — 1번
};

/// 아이템 종류별 색 — 도움은 푸른색·초록 계열, 방해는 경고색 계열
const Map<ItemType, Color> kItemColors = {
  ItemType.invincibleBall: Color(0xFF7CF9FF), // 1 ◉ 밝은 시안 (2026-09-03 강화)
  ItemType.multiBall: Color(0xFF6FC3FF), //      2 ◎ 하늘
  ItemType.slowBall: Color(0xFF7BE38B), //       3 ▼ 초록
  ItemType.paddleGrow: Color(0xFF4FD1A5), //     4 ◀▶ 청녹
  ItemType.brickRevive: Color(0xFFFFB03A), //    5 ■■ 주황
  ItemType.reverse: Color(0xFFFF7BAC), //        6 ◐ 자홍
  ItemType.paddleShrink: Color(0xFFFF8A3D), //   7 ▶◀ 주황빨강
  ItemType.fastBall: Color(0xFFFF4D4D), //       8 ▲ 빨강
};

/// 공 기본색 — 패들과 같은 흰빛
const Color kBallColor = Color(0xFFE3E9F0);

/// 무적 중 공 색 — 빨강→주황→노랑을 돌며 불타는 느낌을 낸다 (2026-09-03).
///
/// 주요 로직 : 공 색은 다른 뜻을 지고 있지 않아 자유롭게 쓸 수 있다.
///   아이템 기호 쪽은 도움=푸른·초록 갈래를 지켜야 하므로 빨강을 쓸 수 없고,
///   증속(▲)이 이미 빨강이라 헷갈린다. 그래서 **강함은 공으로만** 표현한다.
const List<Color> kInvincibleBallColors = [
  Color(0xFFFF3B3B),
  Color(0xFFFF8A3D),
  Color(0xFFFFD24D),
];

class BrickPainter extends CustomPainter {
  BrickPainter(this.state);

  final BrickState state;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF12161C));

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFF2E3742)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (final b in state.bricks) {
      if (!b.alive) continue;
      final rect = state.brickRect(b);
      // 주요 로직 : 안쪽을 채우지 않고 굵은 테두리로만 종류(색)를 나타낸다.
      //   채우면 그 위에 그린 아이템 기호가 색에 묻혀 잘 보이지 않는다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(4)),
        Paint()
          ..color = kBrickColors[b.hp] ?? kBrickColors[1]!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // 아이템을 품은 벽돌은 표시해 준다 — 먼저 깨거나 피하는 선택이 생기도록
      if (b.item != null) {
        drawItemMark(canvas, rect.center, b.item!, 6);
      }
    }

    for (final it in state.fallingItems) {
      drawItemMark(canvas, it.pos, it.type, FallingItem.radius);
    }

    // 끝난 뒤에는 패들과 공을 지운다 — 남은 벽돌만 결과로 보여 준다
    if (state.isFinished) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(state.paddleRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFE3E9F0),
    );

    // 무적 중에는 공이 빨강 계열 3색을 돌며 번쩍인다.
    final flashIdx = state.invincibleColorIndex;
    final ballColor =
        flashIdx == null ? kBallColor : kInvincibleBallColors[flashIdx];
    for (final ball in state.balls) {
      canvas.drawCircle(ball.pos, ball.radius, Paint()..color = ballColor);
    }
  }

  @override
  bool shouldRepaint(covariant BrickPainter old) => true;
}

/// 아이템 표시 — 종류마다 다른 기호를 그린다.
///
/// 주요 로직 : 색만으로는 8종을 순간에 구분할 수 없다.
///   모양으로 종류를 알아보게 하고, 색으로 도움(푸른·초록)과
///   방해(경고색)의 갈래를 한 번 더 구분한다.
///
///   1 ● 무적공   2 ◎ 멀티공   3 ▼ 속도감소  4 ◀▶ 패들확대
///   5 ■■ 벽돌부활 6 ◐ 반전     7 ▶◀ 패들축소 8 ▲ 속도증가
void drawItemMark(Canvas canvas, Offset c, ItemType type, double s) {
  final paint = Paint()..color = kItemColors[type] ?? Colors.white;
  switch (type) {
    case ItemType.invincibleBall: // ◉ 채운 원 + 바깥 얇은 링
      // 2026-09-03 — 그냥 채운 원이라 눈에 안 띈다는 지적. 링을 둘러 굵게 보이게 했다.
      //   멀티공(◎)과 헷갈리지 않게, 이쪽은 **안이 크고 링이 얇다**.
      canvas.drawCircle(c, s * 0.6, paint);
      canvas.drawCircle(
        c,
        s * 0.92,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.16,
      );
    case ItemType.multiBall: // ◎
      canvas.drawCircle(
        c,
        s * 0.85,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.32,
      );
      canvas.drawCircle(c, s * 0.3, paint);
    case ItemType.slowBall: // ▼
      _triangle(canvas, c, s, paint, down: true);
    case ItemType.fastBall: // ▲
      _triangle(canvas, c, s, paint, down: false);
    case ItemType.paddleGrow: // ◀ ▶ (바깥쪽)
      _sideTriangle(canvas, c.translate(-s * 0.75, 0), s * 0.8, paint, left: true);
      _sideTriangle(canvas, c.translate(s * 0.75, 0), s * 0.8, paint, left: false);
    case ItemType.paddleShrink: // ▶ ◀ (안쪽)
      _sideTriangle(canvas, c.translate(-s * 0.75, 0), s * 0.8, paint, left: false);
      _sideTriangle(canvas, c.translate(s * 0.75, 0), s * 0.8, paint, left: true);
    case ItemType.brickRevive: // ■ ■
      final w = s * 0.7;
      canvas.drawRect(
        Rect.fromCenter(center: c.translate(-s * 0.6, 0), width: w, height: w),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: c.translate(s * 0.6, 0), width: w, height: w),
        paint,
      );
    case ItemType.reverse: // ◐
      canvas.drawCircle(
        c,
        s * 0.9,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.25,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: s * 0.9),
        pi / 2,
        pi,
        true,
        paint,
      );
  }
}

void _triangle(Canvas canvas, Offset c, double s, Paint p,
    {required bool down}) {
  final dir = down ? 1.0 : -1.0;
  final path = Path()
    ..moveTo(c.dx, c.dy + s * dir)
    ..lineTo(c.dx + s, c.dy - s * 0.8 * dir)
    ..lineTo(c.dx - s, c.dy - s * 0.8 * dir)
    ..close();
  canvas.drawPath(path, p);
}

void _sideTriangle(Canvas canvas, Offset c, double s, Paint p,
    {required bool left}) {
  final dir = left ? -1.0 : 1.0;
  final path = Path()
    ..moveTo(c.dx + s * dir, c.dy)
    ..lineTo(c.dx - s * 0.8 * dir, c.dy - s)
    ..lineTo(c.dx - s * 0.8 * dir, c.dy + s)
    ..close();
  canvas.drawPath(path, p);
}

/// 아이템 기호를 위젯으로 — 상단 효과 표시에 쓴다
class ItemMark extends StatelessWidget {
  const ItemMark(this.type, {this.size = 16, super.key});

  final ItemType type;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _ItemMarkPainter(type),
      );
}

class _ItemMarkPainter extends CustomPainter {
  _ItemMarkPainter(this.type);

  final ItemType type;

  @override
  void paint(Canvas canvas, Size size) {
    drawItemMark(canvas, size.center(Offset.zero), type, size.width / 2 - 1);
  }

  @override
  bool shouldRepaint(covariant _ItemMarkPainter old) => old.type != type;
}
