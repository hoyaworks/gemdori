import 'package:flutter/material.dart';

import 'account.dart';

// ═══════════════════════════════════════════════════════════════════
//  profile_screen.dart — PROFILE 탭 : 내 정보
// ═══════════════════════════════════════════════════════════════════
//
//  주요 기능 : 닉네임 · 계정 종류(GUEST / MEMBER) · 아이디를 보여준다
//  제외 사항 : 아이디 발급·로그인·닉네임 변경 (다음 단계) · 보일 모양 계산 (account.dart)
//
//  상세 설명 : 계정 정보는 `AccountSource` 에게 받아 그리기만 한다.
//    지금은 발급 전이라 닉네임·아이디가 `—` 로 보이는 것이 정상이다 (2026-09-15).
//
//  주요 로직 : 계정을 못 읽으면 **발급 전 게스트로 보인다** — 내 정보 칸이 오류로 막히면
//    게임을 하는 데 아무 문제가 없는데도 앱이 고장 난 것처럼 보인다.
//
// ═══════════════════════════════════════════════════════════════════

/// PROFILE 탭 본문
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, this.source = const PendingAccountSource()});

  /// 계정 정보를 주는 곳 — Firebase 를 붙일 때 여기로 실제 구현을 넘긴다
  final AccountSource source;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Account? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Account account;
    try {
      account = await widget.source.current();
    } catch (_) {
      account = const Account(kind: AccountKind.guest);
    }
    if (!mounted) return;
    setState(() => _account = account);
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null) {
      return const Center(child: CircularProgressIndicator());
    }
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
        Center(
          child: Text(account.displayNickname, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 8),
        Center(child: _KindBadge(label: account.kindLabel)),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ID'),
            trailing: Text(account.displayId),
          ),
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
