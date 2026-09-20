import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/admin_class.dart';
import '../models/teacher_account.dart';
import '../models/teacher_invite.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const double _tabletBreakpoint = 760;

  List<TeacherAccount> _accounts = [];
  List<TeacherInvite> _invites = [];
  List<AdminClass> _classes = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  _AdminView _view = _AdminView.accounts;

  final TextEditingController _searchCtrl = TextEditingController();

  int get _meId => AuthService.instance.currentUser?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ClassRepository.instance.fetchTeachers();
      final invites = await ClassRepository.instance.fetchInvites();
      final classes = await ClassRepository.instance.fetchAllClasses();
      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _invites = invites;
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(e);
      });
    }
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Something went wrong. Try again.',
      };

  List<TeacherAccount> get _visible {
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? [..._accounts]
        : _accounts
            .where((a) =>
                a.fullName.toLowerCase().contains(q) ||
                a.email.toLowerCase().contains(q) ||
                (a.department ?? '').toLowerCase().contains(q))
            .toList();

    rows.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return rows;
  }

  Future<void> _inviteTeacher() async {
    final request = await showDialog<_NewAccount>(
      context: context,
      builder: (_) => const _NewAccountDialog(),
    );
    if (request == null || !mounted) return;

    try {
      final created = await ClassRepository.instance.createInvite(
        email: request.email,
        fullName: request.fullName,
        department: request.department,
        isAdmin: request.isAdmin,
        daysValid: request.daysValid,
      );
      if (!mounted) return;
      await _showInviteCode(created);
      if (!mounted) return;
      setState(() => _view = _AdminView.invites);
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _revokeInvite(TeacherInvite invite) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Cancel the invitation for ${invite.fullName}?',
      message: 'The code stops working straight away. You can invite them again later, '
          'which issues a new code.',
      confirmLabel: 'Cancel invitation',
      destructive: true,
      icon: Icons.link_off_rounded,
    );
    if (!ok || !mounted) return;

    try {
      await ClassRepository.instance.revokeInvite(invite.id);
      if (!mounted) return;
      AppToast.show(context, 'Invitation cancelled', type: ToastType.success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _showInviteCode(NewInvite created) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Invitation ready'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${created.invite.fullName}  ·  ${created.invite.email}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border, width: 1.3),
                ),
                child: SelectableText(
                  created.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Give them this code and the e-mail address above. On the login '
                      'screen they tap “I have an invitation code”, then choose their '
                      'own password.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.45),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Valid until ${_longDate(created.invite.expiresAt)}. '
                      'It works once, and only with that e-mail address.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: created.code));
              if (!ctx.mounted) return;
              AppToast.show(ctx, 'Code copied', type: ToastType.success);
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy code'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(TeacherAccount account) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reset the password for ${account.fullName}?',
      message: 'A new temporary password is generated and shown once. Their old password '
          'stops working straight away, and they will be asked to choose a new one the '
          'next time they log in.',
      confirmLabel: 'Reset password',
      icon: Icons.lock_reset_rounded,
    );
    if (!ok || !mounted) return;

    try {
      final temporary = await ClassRepository.instance.resetTeacherPassword(account.id);
      if (!mounted) return;
      await _showTemporaryPassword(
        title: 'Password reset',
        name: account.fullName,
        email: account.email,
        password: temporary,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _setActive(TeacherAccount account, bool active) async {
    if (!active) {
      final ok = await showConfirmDialog(
        context,
        title: 'Deactivate ${account.fullName}?',
        message: 'They are signed out immediately and cannot log in again until the '
            'account is reactivated. Their classes and records are kept.',
        confirmLabel: 'Deactivate',
        destructive: true,
        icon: Icons.person_off_outlined,
      );
      if (!ok || !mounted) return;
    }

    try {
      await ClassRepository.instance.setTeacherActive(account.id, active);
      if (!mounted) return;
      AppToast.show(
        context,
        active ? '${account.fullName} reactivated' : '${account.fullName} deactivated',
        type: ToastType.success,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will be returned to the administrator sign-in.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/admin-login', (r) => false);
  }

  Future<void> _setAdmin(TeacherAccount account, bool isAdmin) async {
    final ok = await showConfirmDialog(
      context,
      title: isAdmin
          ? 'Make ${account.fullName} an administrator?'
          : 'Remove administrator rights from ${account.fullName}?',
      message: isAdmin
          ? 'They will be able to create accounts, deactivate them and reset '
              'passwords — and they will no longer be able to hold classes of '
              'their own. An account that already owns a class cannot be '
              'changed this way.'
          : 'They become a teacher account: able to hold classes, no longer '
              'able to manage accounts.',
      confirmLabel: isAdmin ? 'Make administrator' : 'Remove rights',
      destructive: !isAdmin,
      icon: Icons.admin_panel_settings_outlined,
    );
    if (!ok || !mounted) return;

    try {
      await ClassRepository.instance.setTeacherAdmin(account.id, isAdmin);
      if (!mounted) return;
      AppToast.show(context, 'Role updated', type: ToastType.success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _showTemporaryPassword({
    required String title,
    required String name,
    required String email,
    required String password,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, minWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name  ·  $email',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border, width: 1.3),
                ),
                child: SelectableText(
                  password,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'Write this down or send it now. It is stored only as a hash, so it '
                  'cannot be shown again — a forgotten one has to be reset. The teacher '
                  'is asked to choose their own password at their next login.',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (!ctx.mounted) return;
              AppToast.show(ctx, 'Copied', type: ToastType.success);
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = MediaQuery.sizeOf(context).width >= _tabletBreakpoint;
    final hPad = tablet ? 24.0 : 12.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(

        leading: IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Sign out',
          onPressed: _signOut,
        ),
        titleSpacing: 4,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Accounts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.15,
              ),
            ),
            Text(
              'Faculty accounts for this school',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
          if (tablet)
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: ElevatedButton.icon(
                onPressed: _inviteTeacher,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                label: const Text('Invite teacher'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            )
          else ...[
            IconButton.filled(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Invite teacher',
              onPressed: _inviteTeacher,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(42, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AdminNote(),
                  const SizedBox(height: 14),
                  _ViewSwitch(
                    view: _view,
                    accountCount: _accounts.length,
                    pendingCount: _invites.where((i) => i.isPending).length,
                    classCount: _classes.length,
                    strandedCount: _classes.where((c) => c.isStranded).length,
                    onChanged: (v) => setState(() => _view = v),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: _view == _AdminView.classes
                          ? 'Search subject, section or teacher…'
                          : 'Search name, email or department…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: _body(tablet)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool tablet) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_view == _AdminView.invites) return _inviteList(tablet);
    if (_view == _AdminView.classes) return _classList(tablet);

    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _query.trim().isEmpty
              ? 'No accounts yet.'
              : 'No account matches “${_query.trim()}”.',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _AccountTile(
        account: rows[i],
        isMe: rows[i].id == _meId,
        wide: tablet,
        onResetPassword: () => _resetPassword(rows[i]),
        onSetActive: (v) => _setActive(rows[i], v),
        onSetAdmin: (v) => _setAdmin(rows[i], v),
      ),
    );
  }

  List<AdminClass> get _visibleClasses {
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? [..._classes]
        : _classes
            .where((c) =>
                c.subjectCode.toLowerCase().contains(q) ||
                c.subjectName.toLowerCase().contains(q) ||
                c.yearSection.toLowerCase().contains(q) ||
                c.course.toLowerCase().contains(q) ||
                c.teacherName.toLowerCase().contains(q))
            .toList();

    rows.sort((a, b) {
      if (a.isStranded != b.isStranded) return a.isStranded ? -1 : 1;
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final byTeacher = a.teacherName.compareTo(b.teacherName);
      if (byTeacher != 0) return byTeacher;
      return a.title.compareTo(b.title);
    });
    return rows;
  }

  Widget _classList(bool tablet) {
    final rows = _visibleClasses;
    if (rows.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.class_outlined, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                _query.trim().isEmpty
                    ? 'No classes yet. They appear here once a teacher creates one.'
                    : 'No class matches \u201c${_query.trim()}\u201d.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final stranded = _classes.where((c) => c.isStranded).length;

    return ListView.separated(
      itemCount: rows.length + (stranded > 0 ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (stranded > 0 && i == 0) return _StrandedBanner(count: stranded);
        final row = rows[i - (stranded > 0 ? 1 : 0)];
        return _ClassTile(
          item: row,
          wide: tablet,
          onTransfer: () => _transferClass(row),
        );
      },
    );
  }

  Future<void> _transferClass(AdminClass item) async {
    final candidates = _accounts
        .where((a) => !a.isAdmin && a.isActive && a.id != item.teacherId)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (candidates.isEmpty) {
      await showConfirmDialog(
        context,
        title: 'No one to hand it to',
        message: 'A class can only be held by an active teacher account, and '
            'there is no other active teacher at the moment. Create or restore '
            'a teacher account first.',
        confirmLabel: 'Got it',
        cancelLabel: 'Close',
        icon: Icons.person_off_outlined,
      );
      return;
    }

    if (!mounted) return;
    final chosen = await showDialog<TeacherAccount>(
      context: context,
      builder: (_) => _TransferDialog(item: item, candidates: candidates),
    );
    if (chosen == null || !mounted) return;

    try {
      await ClassRepository.instance.transferClass(item.id, chosen.id);
      if (!mounted) return;
      AppToast.show(
        context,
        '${item.title} is now held by ${chosen.fullName}',
        type: ToastType.success,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Widget _inviteList(bool tablet) {
    final q = _query.trim().toLowerCase();
    final rows = _invites
        .where((i) =>
            q.isEmpty ||
            i.fullName.toLowerCase().contains(q) ||
            i.email.toLowerCase().contains(q))
        .toList();

    if (rows.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mail_outline_rounded, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                q.isEmpty
                    ? 'No invitations yet. Invite a teacher and give them the code.'
                    : 'No invitation matches “${_query.trim()}”.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _InviteTile(
        invite: rows[i],
        onRevoke: rows[i].isAccepted ? null : () => _revokeInvite(rows[i]),
      ),
    );
  }
}

String _longDate(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

enum _AdminView { accounts, invites, classes }

class _ViewSwitch extends StatelessWidget {
  final _AdminView view;
  final int accountCount;
  final int pendingCount;
  final int classCount;

  final int strandedCount;

  final ValueChanged<_AdminView> onChanged;

  const _ViewSwitch({
    required this.view,
    required this.accountCount,
    required this.pendingCount,
    required this.classCount,
    required this.strandedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitchTab(
              label: 'Accounts',
              count: accountCount,
              selected: view == _AdminView.accounts,
              onTap: () => onChanged(_AdminView.accounts),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SwitchTab(
              label: 'Invitations',
              count: pendingCount,
              selected: view == _AdminView.invites,
              onTap: () => onChanged(_AdminView.invites),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SwitchTab(
              label: 'Classes',
              count: classCount,
              alert: strandedCount > 0,
              selected: view == _AdminView.classes,
              onTap: () => onChanged(_AdminView.classes),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;

  final bool alert;

  final VoidCallback onTap;

  const _SwitchTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: alert
                      ? AppColors.danger
                      : (selected ? AppColors.primary : AppColors.background),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: (alert || selected) ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final TeacherInvite invite;
  final VoidCallback? onRevoke;

  const _InviteTile({required this.invite, this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final (Color color, Color background, String label, IconData icon) = switch (invite.status) {
      'Accepted' => (AppColors.success, AppColors.successBg, 'Accepted', Icons.check_circle_outline_rounded),
      'Expired' => (AppColors.textMuted, AppColors.background, 'Expired', Icons.schedule_rounded),
      _ => (AppColors.warning, AppColors.warningBg, 'Waiting', Icons.hourglass_bottom_rounded),
    };

    return Opacity(
      opacity: invite.isExpired ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    invite.email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      StatusBadge(
                        label: invite.isPending
                            ? '$label · ${invite.daysLeft} day${invite.daysLeft == 1 ? '' : 's'} left'
                            : label,
                        color: color,
                        background: background,
                        icon: icon,
                      ),
                      if (invite.isAdmin)
                        const StatusBadge(
                          label: 'Administrator',
                          color: AppColors.primary,
                          background: AppColors.primaryLight,
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                      if (invite.invitedBy.isNotEmpty)
                        StatusBadge(
                          label: 'By ${invite.invitedBy}',
                          color: AppColors.textSecondary,
                          background: AppColors.background,
                          icon: Icons.person_outline_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onRevoke != null)
              IconButton(
                onPressed: onRevoke,
                tooltip: invite.isExpired ? 'Remove' : 'Cancel invitation',
                icon: const Icon(Icons.link_off_rounded, size: 19, color: AppColors.danger),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _AdminNote extends StatelessWidget {
  const _AdminNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Teachers do not sign themselves up — you invite them, and they set their '
              'own password from the code you give them. An administrator can invite, '
              'deactivate and reset accounts, but never sees a password and cannot open '
              'another teacher’s classes.',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final TeacherAccount account;
  final bool isMe;
  final bool wide;
  final VoidCallback onResetPassword;
  final ValueChanged<bool> onSetActive;
  final ValueChanged<bool> onSetAdmin;

  const _AccountTile({
    required this.account,
    required this.isMe,
    required this.wide,
    required this.onResetPassword,
    required this.onSetActive,
    required this.onSetAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      account.email,
      if ((account.department ?? '').isNotEmpty) account.department!,
      '${account.classCount} ${account.classCount == 1 ? 'class' : 'classes'}',
    ].join('  ·  ');

    return Opacity(
      opacity: account.isActive ? 1 : 0.65,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Initials(name: account.fullName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? '${account.fullName} (you)' : account.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (account.isAdmin)
                        const StatusBadge(
                          label: 'Administrator',
                          color: AppColors.primary,
                          background: AppColors.primaryLight,
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                      if (!account.isActive)
                        const StatusBadge(
                          label: 'Deactivated',
                          color: AppColors.danger,
                          background: AppColors.dangerBg,
                          icon: Icons.person_off_outlined,
                        ),
                      if (account.mustChangePassword)
                        const StatusBadge(
                          label: 'Temporary password',
                          color: AppColors.warning,
                          background: AppColors.warningBg,
                          icon: Icons.lock_clock_outlined,
                        ),
                      if (account.lastLoginAt != null)
                        StatusBadge(
                          label: 'Last login ${_shortDate(account.lastLoginAt!)}',
                          color: AppColors.textSecondary,
                          background: AppColors.background,
                          icon: Icons.login_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Account actions',
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              color: AppColors.surface,
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: const BorderSide(color: AppColors.border),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'reset':
                    onResetPassword();
                  case 'deactivate':
                    onSetActive(false);
                  case 'activate':
                    onSetActive(true);
                  case 'grant':
                    onSetAdmin(true);
                  case 'revoke':
                    onSetAdmin(false);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Reset password'),
                    ],
                  ),
                ),

                if (!isMe)
                  PopupMenuItem<String>(
                    value: account.isAdmin ? 'revoke' : 'grant',
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text(account.isAdmin
                            ? 'Remove administrator'
                            : 'Make administrator'),
                      ],
                    ),
                  ),
                if (!isMe)
                  PopupMenuItem<String>(
                    value: account.isActive ? 'deactivate' : 'activate',
                    child: Row(
                      children: [
                        Icon(
                          account.isActive
                              ? Icons.person_off_outlined
                              : Icons.person_add_alt_rounded,
                          size: 18,
                          color: account.isActive ? AppColors.danger : AppColors.success,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          account.isActive ? 'Deactivate' : 'Reactivate',
                          style: TextStyle(
                            color:
                                account.isActive ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;

  const _Initials({required this.name});

  @override
  Widget build(BuildContext context) {
    final gradient = AccentPalette.gradientFor(name);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        AccentPalette.initialsFor('', name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

class _NewAccount {
  final String email;
  final String fullName;
  final String? department;
  final bool isAdmin;
  final int daysValid;

  const _NewAccount({
    required this.email,
    required this.fullName,
    this.department,
    this.isAdmin = false,
    this.daysValid = 7,
  });
}

class _NewAccountDialog extends StatefulWidget {
  const _NewAccountDialog();

  @override
  State<_NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends State<_NewAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();
  bool _isAdmin = false;
  int _daysValid = 7;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _department.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _NewAccount(
        email: _email.text.trim(),
        fullName: _name.text.trim(),
        department: _department.text.trim().isEmpty ? null : _department.text.trim(),
        isAdmin: _isAdmin,
        daysValid: _daysValid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: const Text('Invite a teacher'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 320),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Enter the teacher’s name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'name@benilde.edu.ph',
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Enter an email address';
                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                  return ok ? null : 'That email doesn’t look right';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _department,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Department (optional)',
                  hintText: 'e.g. Information Technology',
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text(
                  'Also an administrator',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Can invite and deactivate accounts and reset passwords.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Code expires in',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in [3, 7, 14, 30])
                    ChoiceChip(
                      label: Text('$days days'),
                      selected: _daysValid == days,
                      onSelected: (_) => setState(() => _daysValid = days),
                      backgroundColor: AppColors.surface,
                      selectedColor: AppColors.primaryLight,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _daysValid == days ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'You will get a one-time code to hand over. They choose their own '
                  'password when they use it, so you never see or set it.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Create invitation'),
        ),
      ],
    );
  }
}

class _StrandedBanner extends StatelessWidget {
  final int count;

  const _StrandedBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final many = count != 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_problem_outlined, size: 20, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  many
                      ? '$count classes cannot be opened by anyone'
                      : '1 class cannot be opened by anyone',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  many
                      ? 'Their teachers’ accounts are deactivated, so the records are '
                          'in the system with nobody able to reach them. Hand each one to '
                          'an active teacher.'
                      : 'Its teacher’s account is deactivated, so the records are in '
                          'the system with nobody able to reach them. Hand it to an active '
                          'teacher.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassTile extends StatelessWidget {
  final AdminClass item;
  final bool wide;
  final VoidCallback onTransfer;

  const _ClassTile({
    required this.item,
    required this.wide,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final stranded = item.isStranded;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                item.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (item.isArchived) ...[
              const SizedBox(width: 8),
              const _Pill(label: 'Archived'),
            ],
          ],
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(
              stranded ? Icons.person_off_outlined : Icons.person_outline_rounded,
              size: 15,
              color: stranded ? AppColors.danger : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                stranded
                    ? '${item.teacherName} — account deactivated'
                    : item.teacherName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: stranded ? AppColors.danger : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.groups_outlined, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              '${item.studentCount}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );

    final button = OutlinedButton.icon(
      onPressed: onTransfer,
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: const Text('Hand over'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: stranded ? AppColors.danger : null,
        side: BorderSide(color: stranded ? AppColors.danger : AppColors.border),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: stranded ? AppColors.danger.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 14),
                button,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 12),
                button,
              ],
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _TransferDialog extends StatefulWidget {
  final AdminClass item;
  final List<TeacherAccount> candidates;

  const _TransferDialog({required this.item, required this.candidates});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    final width = (screen.width - 80).clamp(280.0, 460.0);
    final height = (screen.height - 300).clamp(180.0, 360.0);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      title: const Text('Hand over this class'),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Currently held by ${widget.item.teacherName}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            const Text(
              'Everything moves with the class — students, scores, attendance '
              'and any finalized period. Nothing is recomputed, and the handover '
              'is recorded in the audit trail.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hand it to',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: widget.candidates.length,
                itemBuilder: (context, i) {
                  final t = widget.candidates[i];
                  final picked = _selected == t.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: picked ? AppColors.primaryLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () => setState(() => _selected = t.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          child: Row(
                            children: [
                              Icon(
                                picked
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 19,
                                color: picked
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.fullName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      t.email,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(
                    widget.candidates.firstWhere((t) => t.id == _selected),
                  ),
          child: const Text('Hand over'),
        ),
      ],
    );
  }
}