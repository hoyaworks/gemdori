import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'app_services.dart';
import 'nickname.dart';
import 'player_profile.dart';

// ═══════════════════════════════════════════════════════════════════
//  profile_screen.dart — PROFILE 탭 : 내 정보
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 닉네임(바꾸기 포함) · 계정 종류(GUEST / MEMBER) · 아이디를 보여준다
//  제외 사항 : 아이디 발급·로그인 (firebase_account.dart) · 닉네임 저장·만들기 (player_profile.dart)
//              · 글자 규칙 (nickname.dart) · 보일 모양 계산 (account.dart)
//
//  상세 설명 : 계정·닉네임은 `AppServices` 에서 받아 그리기만 한다.
//    닉네임은 앱을 열 때 `GUEST-####` 로 만들어지고, 연필 버튼으로 바꾼다 (2026-09-15).
//    서비스가 없으면(테스트) 발급 전 게스트로 보이고 연필 버튼도 없다.
//
//  주요 로직 : 계정을 못 읽으면 **발급 전 게스트로 보인다** — 내 정보 칸이 오류로 막히면
//    게임을 하는 데 아무 문제가 없는데도 앱이 고장 난 것처럼 보인다.
//
//  주요 로직 : 입력칸은 **허용 글자 말고는 아예 못 치게** 막는다 — 다 친 뒤에 「틀렸다」고 하지 않는다.
//    그래도 길이가 모자라면 저장 버튼이 꺼져 있다.
//
// ═══════════════════════════════════════════════════════════════════

/// PROFILE 탭 본문
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Account? _account;
  String? _nickname;
  PlayerProfile? _profile;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppServices.maybeOf(context);
    _profile = services?.profile;
    _load(services?.account ?? const PendingAccountSource());
  }

  Future<void> _load(AccountSource source) async {
    Account account;
    try {
      account = await source.current();
    } catch (_) {
      account = const Account(kind: AccountKind.guest);
    }
    if (!mounted) return;
    setState(() => _account = account);
    final name = await _profile?.nickname();
    if (!mounted) return;
    setState(() => _nickname = name);
  }

  Future<void> _editNickname() async {
    final profile = _profile;
    if (profile == null) return;
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: _nickname ?? ''),
    );
    if (entered == null) return;
    final ok = await profile.rename(entered);
    if (!mounted) return;
    if (ok) setState(() => _nickname = entered.trim());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? 'SAVED' : 'SAVE FAILED')));
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final shown = Account(kind: account.kind, id: account.id, nickname: _nickname);
    final canEdit = _profile != null && account.id != null;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(Icons.person, size: 48, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 연필 버튼 폭만큼 왼쪽을 비워 이름이 가운데에 오게 한다
            if (canEdit) const SizedBox(width: 48),
            Text(shown.displayNickname, style: theme.textTheme.headlineSmall),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'EDIT NICKNAME',
                onPressed: _editNickname,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Center(child: _KindBadge(label: shown.kindLabel)),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ID'),
            trailing: Text(shown.displayId),
          ),
        ),
      ],
    );
  }
}

/// 닉네임 바꾸기 창 — 저장하면 입력값을, 취소하면 null 을 돌려준다
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => Nickname.isValid(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('NICKNAME'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: Nickname.maxLength,
        inputFormatters: [FilteringTextInputFormatter.allow(Nickname.allowedChar)],
        decoration: const InputDecoration(helperText: Nickname.hint),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_valid) Navigator.of(context).pop(_controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.of(context).pop(_controller.text.trim()) : null,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

/// 계정 종류 배지 — 테두리만 둘러 글자처럼 가볍게
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, letterSpacing: 1.5),
      ),
    );
  }
}
