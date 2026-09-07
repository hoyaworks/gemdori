// ═══════════════════════════════════════════════════════════════════
//  dev_panel.dart — 개발자 패널 (넓은 화면에서만)
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 게임 오른쪽에 상태 값과 최근 사건을 띄운다.
//              화면이 넓을 때만 나오고, 좁으면 게임만 남는다
//  제외 사항 : 게임 규칙·계산 (전부 BrickState)
//
//  상세 설명 : 목적은 디버깅보다 **개발 과정을 보여주는 것**이다.
//    결과물만 보면 「벽돌깨기 하나」지만, 상태를 한 곳에서 관리하고
//    상태가 소리 대신 사건만 내보낸다는 설계는 이 패널로만 드러난다.
//
//  주요 로직 : 표시 여부를 **디바이스가 아니라 「폭이 남는가」로** 가른다.
//    웹으로 배포하므로 폰도 브라우저로 들어온다 — 「브라우저냐」로는 PC/폰이 안 갈린다.
//    폭이 모자라면 패널을 숨기므로 **게임이 줄어들 일이 없다.**
//    이 방식은 폴더블·태블릿·터치 PC 같은 예외가 생기지 않는다.
//
//  주요 로직 : 치트는 **하단 바에서 이걸로 옮겨 왔다** (2026-09-07).
//    하단 바가 없어져 경기장 세로가 40px 늘고, 좁은 화면(폰)에서는 치트가 아예
//    안 보인다 — 원래 보여줄 것이 아니었으므로 이 편이 맞다.
//    크기 전환(S·M·L)만은 **숫자키 1·2·3** 으로도 되게 해 두었다.
//
//  주요 로직 : 사건 로그는 **같은 사건이 이어지면 한 줄에 ×N 으로 합친다.**
//    벽 반사는 초당 몇 번씩 들어와, 합치지 않으면 열두 줄이 전부 wallHit 이 되고
//    정작 보고 싶은 아이템·벽돌 사건이 한 프레임 만에 밀려 사라진다.
//
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'brick_painter.dart';
import 'brick_state.dart';
import 'item.dart';

/// 패널을 켤 것인가.
///
/// 주요 로직 : 지금은 항상 켜 두되 **스위치 자리만** 만들어 둔다 (2026-09-07).
///   배포 때 `kDebugMode` 로 바꾸면 한 줄로 꺼진다 — 끄는 자리를 화면 코드
///   여기저기서 찾아다니지 않게 하려는 것.
const bool devPanelEnabled = true;

/// 최근 사건 목록. 화면이 들고 있고 패널이 읽기만 한다.
///
/// 주요 로직 : 상태(BrickState)에 두지 않는다 — 상태는 **사건을 남기고 잊는** 쪽이고,
///   무엇을 얼마나 보관할지는 보여주는 쪽 사정이다.
class EventLog {
  EventLog({this.capacity = 12});

  /// 보관할 줄 수. 늘리면 매 프레임 그리는 양이 그대로 늘어난다
  final int capacity;

  final List<EventLogLine> _lines = [];

  /// 최근 것이 **앞**에 오도록 뒤집어 준다 — 위에서부터 읽게
  List<EventLogLine> get lines => List.unmodifiable(_lines.reversed);

  void add(GameEvent e) {
    final label = _label(e);
    if (_lines.isNotEmpty && _lines.last.label == label) {
      _lines.last.count++;
      return;
    }
    _lines.add(EventLogLine(label));
    if (_lines.length > capacity) _lines.removeAt(0);
  }

  void addAll(Iterable<GameEvent> events) => events.forEach(add);

  void clear() => _lines.clear();

  /// `brickBroken hp:2` 처럼 — 같은 줄로 합칠지의 기준도 이 문자열이다
  static String _label(GameEvent e) {
    final name = e.type.name;
    return e.hp == 0 ? name : '$name hp:${e.hp}';
  }
}

/// 로그 한 줄. 같은 사건이 이어지면 [count] 만 오른다
class EventLogLine {
  EventLogLine(this.label);

  final String label;
  int count = 1;

  @override
  String toString() => count == 1 ? label : '$label ×$count';
}

class DevPanel extends StatelessWidget {
  const DevPanel({
    required this.state,
    required this.log,
    required this.preset,
    required this.onCheat,
    required this.onPreset,
    super.key,
  });

  final BrickState state;
  final EventLog log;

  /// 지금 걸려 있는 크기 단계 — 버튼 강조에만 쓴다
  final FieldPreset preset;

  /// 상태를 바꾸는 치트를 실행한다.
  ///
  /// 주요 로직 : 패널이 직접 `setState` 를 부를 수 없어 화면에 넘긴다.
  ///   화면 쪽에서 갱신과 **초점 되돌리기**를 함께 한다 — 안 되돌리면
  ///   버튼을 한 번 누른 뒤로 스페이스·숫자키가 먹지 않는다.
  final void Function(VoidCallback action) onCheat;

  final void Function(FieldPreset preset) onPreset;

  /// 패널 폭(px). 고정이다 — 남는 공간을 나눠 가지면 게임 크기가 창에 따라 흔들린다
  static const double width = 300;

  /// 게임과의 사이 여백
  static const double gap = 12;

  /// 이 폭이면 패널을 띄워도 되는가.
  ///
  /// 주요 로직 : 기준은 **패널을 뺀 나머지가 경기장 가로 상한을 감당하는가** 다.
  ///   「몇 인치 이상」이 아니라 이 한 줄이 판별의 전부다.
  ///   대략 660px 부터 뜨고, 폰 세로(360~430)는 자동으로 게임만 남는다.
  static bool fitsIn(double totalWidth) =>
      totalWidth - (width + gap) >= BrickState.maxFieldWidth;

  static const Color _bg = Color(0xFF11161D);
  static const Color _dim = Color(0xFF7A8699);
  static const Color _fg = Color(0xFFBFC7D5);
  static const Color _accent = Color(0xFF7BE38B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('STATE'),
          const SizedBox(height: 6),
          _rows(),
          const SizedBox(height: 6),
          _effects(),
          const SizedBox(height: 14),
          _title('EVENTS'),
          const SizedBox(height: 6),
          Expanded(child: _eventList()),
          const SizedBox(height: 12),
          _title('CHEATS'),
          const SizedBox(height: 6),
          _cheats(),
          const SizedBox(height: 10),
          _note(),
        ],
      ),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
          color: _accent,
        ),
      );

  /// 상태 값 — 한 곳(BrickState)에서 전부 읽어 온다.
  /// 여기서 계산해 만드는 값이 하나도 없다는 것이 이 패널이 보여주려는 것이다.
  Widget _rows() {
    final f = state.fieldSize;
    return Column(
      children: [
        _row('status', state.paused ? 'paused' : state.status.name),
        _row('stage', state.isSampleStage ? 'SAMPLE' : '${state.stage}'),
        _row('score / lives', '${state.score}  /  ${state.lives}'),
        _row('speed', '${state.speedStage + 1}  ${state.speedMark}'),
        _row('field', '${f.width.round()}×${f.height.round()}'
            '   ×${state.scale.toStringAsFixed(2)}'),
        _row('balls / bricks', '${state.balls.length}  /  ${state.remainingBricks}'),
        _row('falling', '${state.fallingItems.length}'),
      ],
    );
  }

  Widget _row(String name, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(name,
                  style: const TextStyle(fontSize: 11, color: _dim)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 11, color: _fg)),
            ),
          ],
        ),
      );

  /// 걸려 있는 효과와 남은 시간.
  ///
  /// 주요 로직 : 상단 표시줄(hudEffects)과 달리 **버프·장비를 가리지 않고 전부** 낸다.
  ///   상단은 플레이어용이라 화면으로 알 수 있는 것(멀티공·패들 폭)을 뺐지만,
  ///   여기는 「지금 상태에 무엇이 들어 있나」를 보여주는 자리다.
  Widget _effects() {
    if (state.effects.isEmpty) {
      return _row('effects', '—');
    }
    return Column(
      children: [
        for (final t in ItemType.values)
          if (state.effects.containsKey(t))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  const SizedBox(width: 96 - 22),
                  ItemMark(t, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t.name}   ${_left(state.effects[t]!)}',
                      style: const TextStyle(fontSize: 11, color: _fg),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 무기한형(untilLost)은 남은 시간이 무한이라 숫자로 낼 수 없다
  static String _left(double seconds) =>
      seconds.isInfinite ? '∞' : '${seconds.toStringAsFixed(1)}s';

  Widget _eventList() {
    final lines = log.lines;
    if (lines.isEmpty) {
      return const Text('—', style: TextStyle(fontSize: 11, color: _dim));
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(
          '${lines[i]}',
          style: TextStyle(
            fontSize: 11,
            // 맨 위(가장 최근) 한 줄만 밝게 — 눈이 어디를 볼지 정해 준다
            color: i == 0 ? _fg : _dim,
          ),
        ),
      ),
    );
  }

  /// 치트 — 상황을 손으로 만들려면 한 판을 다 해야 해서 확인이 느리다.
  /// 목숨·점수 정합성은 따지지 않는다.
  Widget _cheats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 크기 — 화면이 난이도를 바꾸지 않는지 보는 용도. 숫자키 1·2·3 과 같다
        Row(
          children: [
            const SizedBox(
              width: 44,
              child: Text('size', style: TextStyle(fontSize: 11, color: _dim)),
            ),
            for (final p in FieldPreset.values)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _sizeButton(p),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // 스테이지 — 좌우로 옮기고, SAMPLE 은 아이템 시험 전용
        Row(
          children: [
            const SizedBox(
              width: 44,
              child: Text('stage', style: TextStyle(fontSize: 11, color: _dim)),
            ),
            _iconButton(Icons.chevron_left,
                () => state.debugGoToStage(state.stage - 1)),
            SizedBox(
              width: 52,
              child: Text(
                state.isSampleStage ? 'SAMPLE' : '${state.stage}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _fg),
              ),
            ),
            _iconButton(Icons.chevron_right,
                () => state.debugGoToStage(state.stage + 1)),
            const SizedBox(width: 4),
            _textButton('SAMPLE', state.debugLoadSampleStage),
          ],
        ),
        const SizedBox(height: 4),
        // 끝난 화면 — 두 상태를 바로 만든다
        Row(
          children: [
            const SizedBox(
              width: 44,
              child: Text('end', style: TextStyle(fontSize: 11, color: _dim)),
            ),
            _textButton('GAME OVER', state.debugGameOver),
            const SizedBox(width: 4),
            _textButton('CLEARED', state.debugClearStage),
          ],
        ),
      ],
    );
  }

  /// 지금 단계는 테두리로 표시한다 — 색만 바꾸면 어느 쪽이 켜진 건지 헷갈린다
  Widget _sizeButton(FieldPreset p) {
    final on = p == preset;
    final label = switch (p) {
      FieldPreset.small => 'S',
      FieldPreset.medium => 'M',
      FieldPreset.large => 'L',
    };
    return SizedBox(
      width: 34,
      height: 26,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: on ? _accent : const Color(0xFF2A323D)),
          foregroundColor: on ? _accent : _dim,
        ),
        onPressed: () => onPreset(p),
        child: Text('$label${p.index + 1}',
            style: const TextStyle(fontSize: 10, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback action) => IconButton(
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
        color: _dim,
        icon: Icon(icon),
        onPressed: () => onCheat(action),
      );

  Widget _textButton(String text, VoidCallback action) => TextButton(
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: _dim,
        ),
        onPressed: () => onCheat(action),
        child: Text(text, style: const TextStyle(fontSize: 10)),
      );

  Widget _note() => const Text(
        '상태는 소리를 내지 않는다.\n무슨 일이 있었는지만 남기고, 재생은 화면이 맡는다.',
        style: TextStyle(fontSize: 10, height: 1.5, color: _dim),
      );
}
