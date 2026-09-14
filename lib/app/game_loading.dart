// ═══════════════════════════════════════════════════════════════════
//  game_loading.dart — 게임에 들어갈 때의 로딩 막 (공통 규칙)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 준비가 끝날 때까지 화면을 덮고 **조작을 막는다**
//  제외 사항 : 무엇을 준비할지 (게임마다 다르다 — `prepareGame()` 에서 각자 정한다)
//
//  ⭐ 상세 설명 : **게임을 추가하면 전부 이 규칙을 따른다** (2026-09-07 확정).
//    게임마다 달라지는 것은 「무엇을 미리 받아 두는가」 하나뿐이고,
//    덮는 방식·조작 차단·최소 표시 시간은 여기 한 곳에서 똑같이 간다.
//
//  ⭐ 주요 로직 : **게임 화면을 먼저 그리고 그 위를 덮는다.**
//    막을 먼저 씌우고 나중에 게임을 그리면, 막이 걷히는 순간 그리기 준비가
//    시작돼 **버벅임이 그때로 옮겨 갈 뿐**이다. 그래서 한 프레임이 실제로
//    그려진 것을 확인한 뒤에 준비를 시작한다.
//
//  ⭐ 주요 로직 : **터치와 키보드를 둘 다 막아야 한다.**
//    막은 화면을 가릴 뿐이라 키보드는 그 아래로 그대로 들어온다.
//    화면만 막으면 스페이스로 게임이 시작돼 버린다.
//    → 각 게임 화면의 키 처리 맨 앞에서 `if (!ready) return;` 로 끊는다.
//
//  주요 로직 : 준비가 빨리 끝나도 **최소 시간은 띄운다** — 막이 깜빡이면
//    「뭔가 잘못됐나」로 읽힌다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// 게임 화면에 붙여 쓰는 로딩 막.
///
/// 쓰는 법 — 세 곳만 손대면 된다.
///   ① `with GameLoadingMixin`
///   ② `initState()` 에서 `startPreparing()`
///   ③ `build()` 의 반환을 `wrapWithLoading(...)` 으로 감싸고,
///      키 처리 맨 앞에 `if (!ready) return;`
mixin GameLoadingMixin<T extends StatefulWidget> on State<T> {
  /// 준비가 끝났는가. **false 인 동안 조작을 받지 않는다**
  bool get ready => _ready;
  bool _ready = false;

  /// 막을 최소한 이만큼은 띄운다
  static const int minLoadingMs = 300;

  /// ⭐ **게임마다 다른 부분** — 미리 받아 둘 것을 여기서 기다린다.
  ///   (소리·이미지·폰트 등. 없으면 그냥 아무것도 안 하면 된다)
  Future<void> prepareGame();

  /// 준비를 시작한다 — `initState()` 에서 부른다
  void startPreparing() {
    _prepare();
  }

  Future<void> _prepare() async {
    final started = DateTime.now();
    final binding = WidgetsBinding.instance;

    await binding.endOfFrame; // ① 게임 화면이 한 번 그려진다 (막 아래에서)
    await prepareGame(); //      ② 게임마다 다른 준비
    await binding.endOfFrame; // ③ 그 사이 밀린 프레임을 흘려보낸다

    final left = minLoadingMs - DateTime.now().difference(started).inMilliseconds;
    if (left > 0) await Future.delayed(Duration(milliseconds: left));
    if (!mounted) return;
    setState(() => _ready = true);
  }

  /// 준비 중이면 [game] 위에 막을 덮어 돌려준다
  Widget wrapWithLoading(Widget game) {
    if (_ready) return game;
    return Stack(fit: StackFit.expand, children: [game, const _LoadingLayer()]);
  }
}

/// 준비가 끝날 때까지 덮는 막.
///
/// 주요 로직 : 반투명으로 둔다 — 아래에 게임이 **이미 그려져 있다**는 것이
///   눈으로도 보이고, 걷힐 때 화면이 갑자기 나타나지 않는다.
class _LoadingLayer extends StatelessWidget {
  const _LoadingLayer();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // 터치·클릭은 여기서 전부 삼킨다 (아래 게임으로 내려가지 않게)
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: const Color(0xE60B0E13),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF7BE38B),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'LOADING',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 3,
                  color: Color(0xFFBFC7D5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
