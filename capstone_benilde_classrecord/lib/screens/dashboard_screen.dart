import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/class_model.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'add_class_screen.dart';
import 'class_detail_screen.dart';

enum _SortMode { recent, name, students }

enum _ViewMode { grid, list }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const double _tabletBreakpoint = 760;
  static const double _desktopBreakpoint = 1120;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();

  List<ClassModel> _classes = [];

  bool _loading = true;

  String? _loadError;
  String _query = '';
  _SortMode _sort = _SortMode.recent;
  _ViewMode _view = _ViewMode.grid;

  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();

    WidgetsBinding.instance.addPostFrameCallback((_) => _promptForcedPasswordChange());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final classes =
          await ClassRepository.instance.fetchClasses(includeArchived: _showArchived);
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isUnauthorized) {
        await AuthService.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        return;
      }
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _goToAddClass() async {
    final newClass = await Navigator.of(context).push<ClassModel>(
      MaterialPageRoute(builder: (context) => const AddClassScreen()),
    );

    if (newClass == null || !mounted) return;

    try {

      final saved = await ClassRepository.instance.createClass(newClass);
      if (!mounted) return;
      setState(() => _classes.insert(0, saved));
      AppToast.show(
        context,
        '${saved.subjectCode.isNotEmpty ? saved.subjectCode : saved.subjectName} created',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Something went wrong. Try again.',
      };

  void _goToClassDetail(ClassModel classModel) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => ClassDetailScreen(classModel: classModel),
          ),
        )
        .then((_) {

          if (mounted) _load();
        });
  }

  Future<void> _editClass(ClassModel classModel) async {
    final edited = await Navigator.of(context).push<ClassModel>(
      MaterialPageRoute(
        builder: (context) => AddClassScreen(existing: classModel),
      ),
    );

    if (edited == null || !mounted) return;

    try {
      await ClassRepository.instance.updateClass(edited);
      if (!mounted) return;
      setState(() {
        final index = _classes.indexWhere((c) => c.id == edited.id);
        if (index != -1) _classes[index] = edited;
      });
      AppToast.show(
        context,
        '${edited.subjectCode.isNotEmpty ? edited.subjectCode : edited.subjectName} updated',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _deleteClass(ClassModel classModel) async {

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteClassDialog(classModel: classModel),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ClassRepository.instance.deleteClass(classModel.id);
      if (!mounted) return;
      setState(() => _classes.remove(classModel));

      AppToast.show(context, '${classModel.subjectName} deleted', type: ToastType.info);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  Future<void> _setArchived(ClassModel classModel, bool archive) async {
    final label = classModel.subjectCode.isNotEmpty
        ? classModel.subjectCode
        : classModel.subjectName;

    if (archive) {
      final ok = await showConfirmDialog(
        context,
        title: 'Archive $label?',
        message: 'It leaves your class list but nothing is deleted. Grades, scores and '
            'attendance stay exactly as they are, and you can restore it any time from '
            '“Show archived”.',
        confirmLabel: 'Archive class',
        icon: Icons.inventory_2_outlined,
      );
      if (!ok || !mounted) return;
    }

    try {
      await ClassRepository.instance.setClassArchived(classModel.id, archive);
      if (!mounted) return;
      setState(() {
        classModel.isArchived = archive;

        if (archive && !_showArchived) _classes.remove(classModel);
      });
      AppToast.show(
        context,
        archive ? '$label archived' : '$label restored',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  void _toggleShowArchived(bool value) {
    setState(() {
      _showArchived = value;

      if (!value) _classes = _classes.where((c) => !c.isArchived).toList();
    });
    if (value) _load();
  }

  Future<void> _promptForcedPasswordChange() async {
    if (!mounted) return;
    if (!(AuthService.instance.currentUser?.mustChangePassword ?? false)) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(forced: true),
    );

    if (!mounted) return;
    if (changed == true) {
      AppToast.show(context, 'Password changed', type: ToastType.success);
      return;
    }

    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && mounted) {
      AppToast.show(context, 'Password changed', type: ToastType.success);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to log in again to manage your classes.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !mounted) return;

    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _perClassHint(String feature) {
    AppToast.show(
      context,
      'Open a class first to view its $feature.',
      type: ToastType.info,
    );
  }

  int get _totalStudents =>
      _classes.fold(0, (sum, c) => sum + c.studentCount);

  int get _scheduledCount =>
      _classes.where((c) => c.hasSchedule || c.schedule != null).length;

  List<ClassModel> get _visibleClasses {
    final q = _query.trim().toLowerCase();
    final result = _classes.where((c) {
      if (q.isEmpty) return true;
      return c.subjectName.toLowerCase().contains(q) ||
          c.subjectCode.toLowerCase().contains(q) ||
          c.course.toLowerCase().contains(q) ||
          c.yearSection.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _SortMode.recent:
        break;
      case _SortMode.name:
        result.sort(
          (a, b) => a.subjectName.toLowerCase().compareTo(
                b.subjectName.toLowerCase(),
              ),
        );
      case _SortMode.students:
        result.sort((a, b) => b.studentCount.compareTo(a.studentCount));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= _desktopBreakpoint;
        final isTablet = width >= _tabletBreakpoint;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: isDesktop
              ? null
              : Drawer(
                  backgroundColor: AppColors.brandBlack,
                  width: 274,
                  child: _SideNav(
                    onPerClassTap: (feature) {
                      Navigator.of(context).pop();
                      _perClassHint(feature);
                    },
                    onLogout: () {
                      Navigator.of(context).pop();
                      _logout();
                    },
                    classCount: _classes.length,
                  ),
                ),
          floatingActionButton: (!isTablet && _classes.isNotEmpty && !_loading)
              ? FloatingActionButton.extended(
                  onPressed: _goToAddClass,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New class'),
                ).animate().fadeIn(duration: 250.ms).scale(
                    begin: const Offset(0.9, 0.9),
                    curve: Curves.easeOut,
                  )
              : null,
          body: Row(
            children: [
              if (isDesktop)
                _SideNav(
                  onPerClassTap: _perClassHint,
                  onLogout: _logout,
                  classCount: _classes.length,
                ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      showMenuButton: !isDesktop,
                      showHeaderCta: isTablet,
                      onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                      onAddClass: _goToAddClass,
                      onLogout: _logout,
                      onChangePassword: _changePassword,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: _buildContent(width, isDesktop, isTablet),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(double width, bool isDesktop, bool isTablet) {
    final horizontal = isDesktop ? 32.0 : (isTablet ? 24.0 : 18.0);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        isTablet ? 24 : 18,
        horizontal,
        110,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroBanner(
                classCount: _classes.length,
                studentCount: _totalStudents,
                compact: !isTablet,
              ).animate().fadeIn(duration: 350.ms).slideY(
                    begin: 0.04,
                    end: 0,
                    curve: AppMotion.curve,
                  ),

              SizedBox(height: isTablet ? 24 : 18),

              _StatGrid(
                loading: _loading,
                items: [
                  _StatData(
                    icon: Icons.menu_book_rounded,
                    label: 'Classes',
                    value: '${_classes.length}',
                    caption: 'handled this term',
                    color: AppColors.primary,
                    background: AppColors.primaryLight,
                  ),
                  _StatData(
                    icon: Icons.groups_rounded,
                    label: 'Students',
                    value: '$_totalStudents',
                    caption: 'enrolled in total',
                    color: const Color(0xFF1D4ED8),
                    background: const Color(0xFFEAF0FE),
                  ),
                  _StatData(
                    icon: Icons.event_available_rounded,
                    label: 'Scheduled',
                    value: '$_scheduledCount/${_classes.length}',
                    caption: 'classes with a schedule',
                    color: const Color(0xFF0E7490),
                    background: const Color(0xFFE6F5F8),
                  ),
                ],
              ),

              SizedBox(height: isTablet ? 32 : 24),

              _SectionHeader(
                title: 'My classes',
                subtitle: _loading
                    ? 'Loading your workspace…'
                    : _classes.isEmpty
                        ? 'Nothing here yet — create your first class to begin'
                        : '${_visibleClasses.length} of ${_classes.length} shown',
              ),
              const SizedBox(height: 14),

              if (!_loading && (_classes.isNotEmpty || _showArchived)) ...[
                _Toolbar(
                  controller: _searchController,
                  sort: _sort,
                  view: _view,
                  isTablet: isTablet,
                  showArchived: _showArchived,
                  onQueryChanged: (value) => setState(() => _query = value),
                  onSortChanged: (mode) => setState(() => _sort = mode),
                  onViewChanged: (mode) => setState(() => _view = mode),
                  onShowArchivedChanged: _toggleShowArchived,
                ),
                const SizedBox(height: 18),
              ],

              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.curve,
                child: _loading
                    ? _SkeletonGrid(
                        key: const ValueKey('skeleton'),
                        columns: _columnsFor(isDesktop, isTablet),
                      )
                    : _loadError != null
                    ? _LoadErrorState(
                        key: const ValueKey('error'),
                        message: _loadError!,
                        onRetry: _load,
                      )
                    : _classes.isEmpty
                        ? _EmptyState(
                            key: const ValueKey('empty'),
                            onAddClass: _goToAddClass,
                          )
                        : _visibleClasses.isEmpty
                            ? _NoResultsState(
                                key: const ValueKey('no-results'),
                                query: _query,
                                onClear: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : _ClassCollection(
                                key: ValueKey(
                                  'data-${_view.name}-${_sort.name}-$_query-${_visibleClasses.length}',
                                ),
                                classes: _visibleClasses,
                                columns: _view == _ViewMode.list
                                    ? 1
                                    : _columnsFor(isDesktop, isTablet),
                                onOpen: _goToClassDetail,
                                onEdit: _editClass,
                                onDelete: _deleteClass,
                                onArchive: _setArchived,
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _columnsFor(bool isDesktop, bool isTablet) {
    if (isDesktop) return 3;
    if (isTablet) return 2;
    return 1;
  }
}

class _SideNav extends StatelessWidget {
  final ValueChanged<String> onPerClassTap;
  final VoidCallback onLogout;
  final int classCount;

  const _SideNav({
    required this.onPerClassTap,
    required this.onLogout,
    required this.classCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.brandBlack, Color(0xFF0B1913)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DotGridPainter(
                color: Colors.white.withValues(alpha: 0.035),
                spacing: 24,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.5),
                            width: 1.4,
                          ),
                        ),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ClassRecord',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'ST. BENILDE',
                              style: TextStyle(
                                color: AppColors.gold.withValues(alpha: 0.95),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 26),
                _navLabel('WORKSPACE'),
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'My classes',
                  selected: true,
                  trailing: classCount > 0 ? '$classCount' : null,
                  onTap: () {},
                ),

                const SizedBox(height: 20),
                _navLabel('PER CLASS'),
                _NavItem(
                  icon: Icons.fact_check_outlined,
                  label: 'Attendance',
                  onTap: () => onPerClassTap('attendance'),
                ),
                _NavItem(
                  icon: Icons.grade_outlined,
                  label: 'Grades',
                  onTap: () => onPerClassTap('grades'),
                ),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Schedule',
                  onTap: () => onPerClassTap('schedule'),
                ),

                const Spacer(),

                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'T',
                            style: TextStyle(
                              color: AppColors.brandBlack,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Teacher',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Faculty account',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Log out',
                          child: IconButton(
                            onPressed: onLogout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            style: IconButton.styleFrom(
                              foregroundColor:
                                  Colors.white.withValues(alpha: 0.7),
                              minimumSize: const Size(36, 36),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? trailing;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) {
        final active = selected || hovered;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.12)
                      : hovered
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [

                    AnimatedContainer(
                      duration: AppMotion.fast,
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Icon(
                      icon,
                      size: 19,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.62),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.72),
                          fontSize: 14.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          trailing!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool showMenuButton;
  final bool showHeaderCta;
  final VoidCallback onMenu;
  final VoidCallback onAddClass;
  final VoidCallback onLogout;
  final VoidCallback onChangePassword;

  const _TopBar({
    required this.showMenuButton,
    required this.showHeaderCta,
    required this.onMenu,
    required this.onAddClass,
    required this.onLogout,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1.2),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(showMenuButton ? 8 : 24, 10, 14, 10),
          child: Row(
            children: [
              if (showMenuButton) ...[
                IconButton(
                  onPressed: onMenu,
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'Open navigation',
                ),
                const SizedBox(width: 2),
              ],

              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Workspace',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Flexible(
                      child: Text(
                        'My classes',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (showHeaderCta) ...[
                ElevatedButton.icon(
                  onPressed: onAddClass,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('New class'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              PopupMenuButton<String>(
                tooltip: 'Account',
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: const BorderSide(color: AppColors.border),
                ),
                color: AppColors.surface,
                onSelected: (value) {
                  if (value == 'password') onChangePassword();
                  if (value == 'logout') onLogout();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AuthService.instance.currentUser?.fullName ?? 'Teacher',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
                          ),
                        ),
                        Text(
                          'Faculty account',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'password',
                    child: Row(
                      children: [
                        Icon(Icons.lock_reset_rounded, size: 18, color: AppColors.textSecondary),
                        SizedBox(width: 10),
                        Text('Change password', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Log out',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'T',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
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

class _HeroBanner extends StatelessWidget {
  final int classCount;
  final int studentCount;
  final bool compact;

  const _HeroBanner({
    required this.classCount,
    required this.studentCount,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.brandBlack,
                AppColors.primaryDark,
                AppColors.primary,
              ],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: DotGridPainter(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                right: -50,
                top: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.14),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 20 : 30),

                child: _copy(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _copy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_greeting()}, Teacher',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 23 : 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          classCount == 0
              ? 'Set up your first class to start tracking attendance and grades.'
              : 'You are handling $classCount ${classCount == 1 ? 'class' : 'classes'} '
                  'and $studentCount ${studentCount == 1 ? 'student' : 'students'} this term.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 14.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _StatData {
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;
  final Color background;

  const _StatData({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.background,
  });
}

class _StatGrid extends StatelessWidget {
  final List<_StatData> items;
  final bool loading;

  const _StatGrid({required this.items, required this.loading});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {

        final columns = constraints.maxWidth >= 720 ? items.length : 1;
        const gap = 14.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: itemWidth,
                child: loading
                    ? const _StatSkeleton()
                    : _StatCard(data: items[i])
                        .animate()
                        .fadeIn(delay: (70 * i).ms, duration: 350.ms)
                        .slideY(begin: 0.10, end: 0, curve: AppMotion.curve),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatData data;

  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      enableCursor: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color:
                hovered ? data.color.withValues(alpha: 0.35) : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: data.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(data.icon, size: 19, color: data.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              data.value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              data.caption,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              SkeletonBox(width: 38, height: 38, radius: AppRadius.sm),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 12)),
            ],
          ),
          SizedBox(height: 18),
          SkeletonBox(width: 70, height: 26),
          SizedBox(height: 10),
          SkeletonBox(width: 110, height: 10),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _SortMode sort;
  final _ViewMode view;
  final bool isTablet;
  final bool showArchived;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_SortMode> onSortChanged;
  final ValueChanged<_ViewMode> onViewChanged;
  final ValueChanged<bool> onShowArchivedChanged;

  const _Toolbar({
    required this.controller,
    required this.sort,
    required this.view,
    required this.isTablet,
    required this.showArchived,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onViewChanged,
    required this.onShowArchivedChanged,
  });

  String get _sortLabel {
    switch (sort) {
      case _SortMode.recent:
        return 'Newest first';
      case _SortMode.name:
        return 'Name (A–Z)';
      case _SortMode.students:
        return 'Most students';
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      controller: controller,
      onChanged: onQueryChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search subject, code, course, or section…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 14,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onQueryChanged('');
                },
              ),
      ),
    );

    final sortButton = PopupMenuButton<_SortMode>(
      tooltip: 'Sort classes',
      initialValue: sort,
      offset: const Offset(0, 46),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: onSortChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: _SortMode.recent, child: Text('Newest first')),
        PopupMenuItem(value: _SortMode.name, child: Text('Name (A–Z)')),
        PopupMenuItem(value: _SortMode.students, child: Text('Most students')),
      ],
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border, width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _sortLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );

    final viewSwitch = Container(
      height: 50,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border, width: 1.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewToggle(Icons.grid_view_rounded, 'Grid view', _ViewMode.grid),
          _viewToggle(Icons.view_agenda_outlined, 'List view', _ViewMode.list),
        ],
      ),
    );

    final archivedToggle = FilterChip(
      avatar: Icon(
        showArchived ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
        size: 17,
        color: showArchived ? AppColors.primary : AppColors.textMuted,
      ),
      label: const Text('Show archived'),
      selected: showArchived,
      onSelected: onShowArchivedChanged,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryLight,
      checkmarkColor: AppColors.primary,
      showCheckmark: false,
      side: BorderSide(
        color: showArchived ? AppColors.primary : AppColors.border,
        width: 1.3,
      ),
      labelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: showArchived ? AppColors.primary : AppColors.textSecondary,
      ),
    );

    if (isTablet) {
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 10),
          archivedToggle,
          const SizedBox(width: 10),
          sortButton,
          const SizedBox(width: 10),
          viewSwitch,
        ],
      );
    }

    return Column(
      children: [
        search,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: sortButton),
            const SizedBox(width: 10),
            viewSwitch,
          ],
        ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: archivedToggle),
      ],
    );
  }

  Widget _viewToggle(IconData icon, String tooltip, _ViewMode mode) {
    final selected = view == mode;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: () => onViewChanged(mode),
          borderRadius: BorderRadius.circular(7),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassCollection extends StatelessWidget {
  final List<ClassModel> classes;
  final int columns;
  final ValueChanged<ClassModel> onOpen;
  final ValueChanged<ClassModel> onEdit;
  final ValueChanged<ClassModel> onDelete;
  final void Function(ClassModel, bool archive) onArchive;

  const _ClassCollection({
    super.key,
    required this.classes,
    required this.columns,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < classes.length; i++)
              SizedBox(
                width: itemWidth,
                child: _ClassCard(
                  classModel: classes[i],
                  onTap: () => onOpen(classes[i]),
                  onEdit: () => onEdit(classes[i]),
                  onDelete: () => onDelete(classes[i]),
                  onArchive: () => onArchive(classes[i], !classes[i].isArchived),
                )
                    .animate()
                    .fadeIn(delay: (45 * i).ms, duration: 320.ms)
                    .slideY(begin: 0.06, end: 0, curve: AppMotion.curve),
              ),
          ],
        );
      },
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassModel classModel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onArchive;

  const _ClassCard({
    required this.classModel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = AccentPalette.gradientFor(
      classModel.subjectCode.isNotEmpty
          ? classModel.subjectCode
          : classModel.subjectName,
    );
    final initials = AccentPalette.initialsFor(
      classModel.subjectCode,
      classModel.subjectName,
    );
    final scheduled = classModel.hasSchedule || classModel.schedule != null;

    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hovered
                ? gradient.first.withValues(alpha: 0.45)
                : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradient,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: [
                            BoxShadow(
                              color: gradient.first.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              classModel.subjectName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              classModel.subjectCode.isNotEmpty
                                  ? classModel.subjectCode
                                  : 'No subject code',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: gradient.first,
                              ),
                            ),
                          ],
                        ),
                      ),

                      PopupMenuButton<String>(
                        tooltip: 'Class actions',
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        color: AppColors.surface,
                        offset: const Offset(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        onSelected: (value) {
                          if (value == 'open') onTap();
                          if (value == 'edit') onEdit();
                          if (value == 'archive') onArchive();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: 'open',
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('Open class'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Edit class'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'archive',
                            child: Row(
                              children: [
                                Icon(
                                  classModel.isArchived
                                      ? Icons.unarchive_outlined
                                      : Icons.inventory_2_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(classModel.isArchived
                                    ? 'Restore class'
                                    : 'Archive class'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: AppColors.danger,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Delete class',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Divider(color: AppColors.border.withValues(alpha: 0.9)),
                  const SizedBox(height: 14),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (classModel.isArchived)
                        const StatusBadge(
                          label: 'Archived',
                          color: AppColors.textSecondary,
                          background: AppColors.background,
                          icon: Icons.inventory_2_outlined,
                        ),
                      StatusBadge(
                        label: classModel.course.isNotEmpty
                            ? classModel.course
                            : 'No course',
                        color: AppColors.textSecondary,
                        background: AppColors.background,
                        icon: Icons.school_outlined,
                      ),
                      StatusBadge(
                        label: classModel.yearSection.isNotEmpty
                            ? classModel.yearSection
                            : 'No section',
                        color: AppColors.textSecondary,
                        background: AppColors.background,
                        icon: Icons.layers_outlined,
                      ),
                      StatusBadge(
                        label:
                            '${classModel.studentCount} ${classModel.studentCount == 1 ? 'student' : 'students'}',
                        color: AppColors.primary,
                        background: AppColors.primaryLight,
                        icon: Icons.groups_outlined,
                      ),
                      StatusBadge(
                        label: scheduled ? 'Scheduled' : 'No schedule',
                        color: scheduled ? AppColors.success : AppColors.warning,
                        background:
                            scheduled ? AppColors.successBg : AppColors.warningBg,
                        icon: scheduled
                            ? Icons.event_available_rounded
                            : Icons.schedule_rounded,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Text(
                        'Open class',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color:
                              hovered ? gradient.first : AppColors.textSecondary,
                        ),
                      ),
                      AnimatedContainer(
                        duration: AppMotion.fast,
                        width: hovered ? 12 : 6,
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: hovered ? gradient.first : AppColors.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  final int columns;

  const _SkeletonGrid({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < columns * 2; i++)
              SizedBox(
                width: itemWidth,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          SkeletonBox(
                            width: 48,
                            height: 48,
                            radius: AppRadius.sm,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(height: 14),
                                SizedBox(height: 8),
                                SkeletonBox(width: 90, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Row(
                        children: [
                          SkeletonBox(width: 76, height: 26, radius: 999),
                          SizedBox(width: 8),
                          SkeletonBox(width: 64, height: 26, radius: 999),
                        ],
                      ),
                      SizedBox(height: 18),
                      SkeletonBox(width: 100, height: 12),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 28,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Couldn’t load your classes',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 240.ms);
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddClass;

  const _EmptyState({super.key, required this.onAddClass});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryLight,
                  AppColors.primaryLight.withValues(alpha: 0.35),
                ],
              ),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              size: 38,
              color: AppColors.primary,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.8, 0.8), curve: AppMotion.curve),
          const SizedBox(height: 22),
          Text(
            'Create your first class',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'A class holds your students, attendance records, and grade '
              'breakdown. You can always edit the details later.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 240,
            child: ElevatedButton.icon(
              onPressed: onAddClass,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('New class'),
            ),
          ),
          const SizedBox(height: 28),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: const [
              _HintChip(
                icon: Icons.person_add_alt_rounded,
                label: '1. Add students',
              ),
              _HintChip(
                icon: Icons.calendar_month_rounded,
                label: '2. Set the schedule',
              ),
              _HintChip(icon: Icons.grade_rounded, label: '3. Track grades'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoResultsState({
    super.key,
    required this.query,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 30,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No classes match “$query”',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different subject, code, course, or section.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Clear search'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteClassDialog extends StatefulWidget {
  final ClassModel classModel;

  const _DeleteClassDialog({required this.classModel});

  @override
  State<_DeleteClassDialog> createState() => _DeleteClassDialogState();
}

class _DeleteClassDialogState extends State<_DeleteClassDialog> {
  final _controller = TextEditingController();

  String get _expected => widget.classModel.subjectCode.trim().isNotEmpty
      ? widget.classModel.subjectCode.trim()
      : widget.classModel.subjectName.trim();

  bool get _matches =>
      _controller.text.trim().toLowerCase() == _expected.toLowerCase();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.classModel;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      icon: const Icon(Icons.delete_forever_outlined, color: AppColors.danger, size: 32),
      title: Text('Delete ${c.subjectName}?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently erases the class and every student, score and '
              'attendance record in it. It cannot be undone.',
              style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(
                    text: _expected,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const TextSpan(text: ' to confirm.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(hintText: _expected),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_matches) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete class'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {

  final bool forced;

  const _ChangePasswordDialog({this.forced = false});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t change the password. Try again.',
        };
      });
    }
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: _show ? 'Hide passwords' : 'Show passwords',
          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _show = !_show),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: Text(widget.forced ? 'Set your own password' : 'Change password'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.forced) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
                  ),
                  child: const Text(
                    'Your account is on a temporary password given to you by the '
                    'administrator. Choose your own password to continue.',
                    style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13.5)),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _current,
                obscureText: !_show,
                enabled: !_saving,
                autofocus: true,
                decoration: _field(
                    widget.forced ? 'Temporary password' : 'Current password'),
                validator: (v) => (v == null || v.isEmpty)
                    ? (widget.forced
                        ? 'Enter the temporary password'
                        : 'Enter your current password')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _next,
                obscureText: !_show,
                enabled: !_saving,
                decoration: _field('New password'),
                validator: (v) {
                  if (v == null || v.length < 8) return 'Use at least 8 characters';
                  if (v.length > 72) return 'Use 72 characters or fewer';
                  if (v == _current.text) return 'Use a password different from the current one';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: !_show,
                enabled: !_saving,
                decoration: _field('Confirm new password'),
                validator: (v) => v != _next.text ? 'The passwords don’t match' : null,
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.forced ? 'Log out instead' : 'Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
              : Text(widget.forced ? 'Save password' : 'Change password'),
        ),
      ],
    );
  }
}