import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/class_model.dart';
import '../models/grading_category_model.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const double _tabletBreakpoint = 760;

String _pct(double weight) {
  final v = weight * 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

IconData _iconFor(GradingCategoryModel c, bool hasChildren) {
  if (c.isAttendance) return Icons.event_available_rounded;
  if (hasChildren) return Icons.folder_outlined;
  final n = c.name.toLowerCase();
  if (n.contains('quiz')) return Icons.quiz_outlined;
  if (n.contains('exam')) return Icons.fact_check_outlined;
  if (n.contains('project')) return Icons.folder_special_outlined;
  if (n.contains('performance') || n.contains('task')) return Icons.task_alt_rounded;
  if (n.contains('activit') || n.contains('seatwork')) return Icons.edit_note_rounded;
  if (n.contains('recit')) return Icons.record_voice_over_outlined;
  if (n.contains('assign')) return Icons.assignment_outlined;
  return Icons.grid_view_rounded;
}

class GradingCategoriesScreen extends StatefulWidget {
  final ClassModel classModel;

  const GradingCategoriesScreen({super.key, required this.classModel});

  @override
  State<GradingCategoriesScreen> createState() => _GradingCategoriesScreenState();
}

class _GradingCategoriesScreenState extends State<GradingCategoriesScreen> {
  ClassModel get _class => widget.classModel;

  List<GradingCategoryModel> get _topLevel =>
      _class.gradingCategories.where((c) => c.parentId == null).toList();

  List<GradingCategoryModel> _childrenOf(String parentId) =>
      _class.gradingCategories.where((c) => c.parentId == parentId).toList();

  double get _total => _topLevel.fold<double>(0, (s, c) => s + c.weight) * 100;

  double _childTotal(String parentId) =>
      _childrenOf(parentId).fold<double>(0, (s, c) => s + c.weight) * 100;

  bool _isBalanced(double total) => (total - 100).abs() <= 0.05;

  int _itemCount(String categoryId) =>
      _class.assessments.where((a) => a.categoryId == categoryId).length;

  Future<void> _editCategory({
    GradingCategoryModel? existing,
    String? parentId,
  }) async {
    final isChild = existing?.parentId != null || parentId != null;
    final locked = existing?.isAttendance == true;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final weightCtrl =
        TextEditingController(text: existing != null ? _pct(existing.weight) : '');
    final formKey = GlobalKey<FormState>();

    final siblings = (isChild
            ? _childrenOf(existing?.parentId ?? parentId!)
            : _topLevel)
        .where((c) => c.id != existing?.id);
    final used = siblings.fold<double>(0, (s, c) => s + c.weight) * 100;
    final remaining = (100 - used).clamp(0, 100).toDouble();

    final saved = await _showDialog<bool>(
      maxWidth: 460,
      builder: (ctx) {
        return _DialogFrame(
          icon: existing == null ? Icons.add_rounded : Icons.edit_outlined,
          title: existing != null
              ? 'Edit ${existing.name}'
              : (isChild ? 'New subcategory' : 'New category'),
          subtitle: isChild
              ? 'Its weight is a share of the parent category, not of the whole grade.'
              : 'Its weight is a share of the final grade.',
          body: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  enabled: !locked,
                  autofocus: !locked,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Give the category a name.' : null,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Quizzes, Recitation, Long exam',
                    helperText: locked ? 'Attendance keeps its name.' : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: weightCtrl,
                  autofocus: locked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null) return 'Enter a number.';
                    if (n <= 0) return 'Weight must be more than 0.';
                    if (n > 100) return 'Weight can’t be more than 100.';
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(ctx).pop(true);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    hintText: 'e.g. 20',
                    suffixText: '%',
                    helperText: remaining <= 0
                        ? 'The other categories already use the full 100%.'
                        : '${_fmt(remaining)}% is still unassigned at this level.',
                    helperMaxLines: 2,
                  ),
                ),
                if (remaining > 0) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => weightCtrl.text = _fmt(remaining),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: Text('Use the remaining ${_fmt(remaining)}%'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              child: Text(existing == null ? 'Add category' : 'Save changes'),
            ),
          ],
        );
      },
    );

    if (saved != true || !mounted) {
      nameCtrl.dispose();
      weightCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    final weight = (double.tryParse(weightCtrl.text.trim()) ?? 0) / 100;

    try {
      if (existing != null) {

        final beforeName = existing.name;
        final beforeWeight = existing.weight;
        setState(() {
          if (!locked) existing.name = name;
          existing.weight = weight;
        });
        try {
          await ClassRepository.instance.updateCategory(_class.id, existing);
        } catch (e) {
          if (mounted) {
            setState(() {
              existing.name = beforeName;
              existing.weight = beforeWeight;
            });
          }
          rethrow;
        }
      } else {

        final created = await ClassRepository.instance.createCategory(
          _class.id,
          name: name,
          weight: weight,
          parentId: parentId,
          sortOrder: _class.gradingCategories.length,
        );
        if (!mounted) return;
        setState(() => _class.gradingCategories.add(created));
      }

      if (!mounted) return;
      AppToast.show(
        context,
        existing != null ? 'Saved $name' : 'Added $name',
        type: ToastType.success,
      );
    } catch (e) {
      _reportFailure(e);
    } finally {
      nameCtrl.dispose();
      weightCtrl.dispose();
    }
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Something went wrong. Try again.',
      };

  void _reportFailure(Object error) {
    if (!mounted) return;
    AppToast.show(context, _messageFor(error), type: ToastType.error);
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _deleteCategory(GradingCategoryModel c) async {
    final children = _childrenOf(c.id);
    if (children.isNotEmpty) {
      await showConfirmDialog(
        context,
        title: 'Remove its subcategories first',
        message: '${c.name} still groups ${children.length} '
            'subcategor${children.length == 1 ? 'y' : 'ies'}: '
            '${children.map((x) => x.name).join(', ')}. Delete those first, or move '
            'their items elsewhere.',
        confirmLabel: 'Got it',
        cancelLabel: 'Close',
        icon: Icons.folder_outlined,
      );
      return;
    }

    final items = _itemCount(c.id);
    if (items > 0) {
      await showConfirmDialog(
        context,
        title: 'This category still has items',
        message: '${c.name} holds $items recorded item${items == 1 ? '' : 's'} with '
            'scores. Delete them from its sheet in the gradebook first, so no grades '
            'are lost by accident.',
        confirmLabel: 'Got it',
        cancelLabel: 'Close',
        icon: Icons.inventory_2_outlined,
      );
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${c.name}?',
      message: 'Its ${_pct(c.weight)}% goes back to unassigned, so the weights will '
          'no longer add up to 100% until you adjust the rest.',
      confirmLabel: 'Delete category',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    try {
      await ClassRepository.instance.deleteCategory(_class.id, c.id);
      if (!mounted) return;
      setState(() => _class.gradingCategories.remove(c));

      AppToast.show(context, 'Deleted ${c.name}');
    } catch (e) {
      _reportFailure(e);
    }
  }

  Future<void> _balanceWeights() async {
    final adjustable = _topLevel.where((c) => !c.isAttendance).toList();
    if (adjustable.isEmpty) {
      AppToast.show(context, 'Add a category first, then the weights can be balanced.');
      return;
    }

    final fixed = _topLevel.where((c) => c.isAttendance).fold<double>(0, (s, c) => s + c.weight);
    final share = (1 - fixed) / adjustable.length;
    if (share <= 0) {
      AppToast.show(
        context,
        'Attendance already takes the full 100%. Lower it first.',
        type: ToastType.error,
      );
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: 'Split the weights evenly?',
      message: 'Each of the ${adjustable.length} categories besides Attendance becomes '
          '${_fmt(share * 100)}%, bringing the total to 100%. Your current weights are replaced.',
      confirmLabel: 'Split evenly',
      icon: Icons.balance_rounded,
    );
    if (!ok || !mounted) return;

    final before = {for (final c in _topLevel) c.id: c.weight};
    setState(() {
      for (final c in adjustable) {
        c.weight = share;
      }
    });

    try {

      for (final c in adjustable) {
        await ClassRepository.instance.updateCategory(_class.id, c);
      }
      if (!mounted) return;
      AppToast.show(context, 'Weights now total 100%', type: ToastType.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final c in _topLevel) {
            final w = before[c.id];
            if (w != null) c.weight = w;
          }
        });
      }
      _reportFailure(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = width >= _tabletBreakpoint;
    final hPad = tablet ? 24.0 : 16.0;
    final topLevel = _topLevel;
    final total = _total;

    return Scaffold(
      appBar: _appBar(tablet),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: topLevel.isEmpty
              ? _emptyState()
              : ListView(
                  padding: EdgeInsets.fromLTRB(hPad, tablet ? 20 : 14, hPad, 40),
                  children: [
                    _intro(tablet),
                    const SizedBox(height: 18),
                    _WeightMeter(
                      categories: topLevel,
                      total: total,
                      balanced: _isBalanced(total),
                      onBalance: _balanceWeights,
                    ),
                    const SizedBox(height: 24),
                    Text('Categories', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      'Each one becomes its own sheet in the gradebook.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < topLevel.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _categoryCard(topLevel[i]),
                    ],
                    const SizedBox(height: 14),
                    _addCard(),
                  ],
                ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool tablet) {
    final c = _class;
    final subtitle = c.subjectCode.isNotEmpty ? '${c.subjectCode}  ${c.subjectName}' : c.subjectName;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 4,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Grading breakdown',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.15),
          ),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
      actions: [
        if (tablet)
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: ElevatedButton.icon(
              onPressed: () => _editCategory(),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('New category'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          )
        else ...[
          IconButton.filled(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New category',
            onPressed: () => _editCategory(),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(42, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _intro(bool tablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How this class is graded',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: tablet ? 24 : 20),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Copy the breakdown from your syllabus. Weights are shares of the final '
            'grade and need to total 100%.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _categoryCard(GradingCategoryModel c) {
    final children = _childrenOf(c.id);
    final isAttendance = c.isAttendance;
    final accent = isAttendance ? AppColors.goldDark : AccentPalette.gradientFor(c.id).first;
    final accentBg = isAttendance ? AppColors.goldLight : accent.withValues(alpha: 0.10);
    final items = _itemCount(c.id);

    final childTotal = children.isEmpty ? 0.0 : _childTotal(c.id);
    final childBalanced = _isBalanced(childTotal);

    return Hoverable(
      enableCursor: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: hovered ? accent.withValues(alpha: 0.4) : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(_iconFor(c, children.isNotEmpty), size: 21, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isAttendance) ...[
                              const SizedBox(width: 8),
                              const Tooltip(
                                message: 'Taken from your attendance records automatically',
                                child: StatusBadge(
                                  label: 'Auto',
                                  color: AppColors.goldDark,
                                  background: AppColors.goldLight,
                                  icon: Icons.sync_rounded,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitleFor(c, children.length, items),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _WeightPill(percent: _pct(c.weight), accent: accent),
                  const SizedBox(width: 4),
                  _actions(c, canGroup: !isAttendance),
                ],
              ),
            ),
            if (children.isNotEmpty)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Subcategories',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        StatusBadge(
                          label: childBalanced
                              ? 'Totals 100%'
                              : '${_fmt(childTotal)}% of 100%',
                          color: childBalanced ? AppColors.success : AppColors.warning,
                          background: childBalanced ? AppColors.successBg : AppColors.warningBg,
                          icon: childBalanced ? Icons.check_rounded : Icons.error_outline_rounded,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final child in children) ...[
                      _childRow(child, accent),
                      const SizedBox(height: 8),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _editCategory(parentId: c.id),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add subcategory'),
                        style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(GradingCategoryModel c, int childCount, int items) {
    if (c.isAttendance) return 'Calculated from the attendance sheet';
    if (childCount > 0) {
      return 'Grouped into $childCount subcategor${childCount == 1 ? 'y' : 'ies'}';
    }
    return items == 0 ? 'No items recorded yet' : '$items item${items == 1 ? '' : 's'} recorded';
  }

  Widget _childRow(GradingCategoryModel child, Color accent) {
    final items = _itemCount(child.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 26, color: accent.withValues(alpha: 0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  items == 0 ? 'No items yet' : '$items item${items == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: '${_pct(child.weight)}% of its parent category',
            child: Text(
              '${_pct(child.weight)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _actions(child, canGroup: false),
        ],
      ),
    );
  }

  Widget _actions(GradingCategoryModel c, {required bool canGroup}) {
    final hasChildren = _childrenOf(c.id).isNotEmpty;
    return PopupMenuButton<String>(
      tooltip: 'Options for ${c.name}',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _editCategory(existing: c);
          case 'sub':
            _editCategory(parentId: c.id);
          case 'delete':
            _deleteCategory(c);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: _MenuRow(
            icon: Icons.edit_outlined,
            label: c.isAttendance ? 'Edit weight' : 'Edit name and weight',
          ),
        ),
        if (canGroup && !hasChildren)
          const PopupMenuItem<String>(
            value: 'sub',
            child: _MenuRow(icon: Icons.account_tree_outlined, label: 'Split into subcategories'),
          ),
        if (canGroup && hasChildren)
          const PopupMenuItem<String>(
            value: 'sub',
            child: _MenuRow(icon: Icons.add_rounded, label: 'Add subcategory'),
          ),
        if (!c.isAttendance) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'delete',
            child: _MenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _addCard() {
    return Hoverable(
      builder: (context, hovered) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _editCategory(),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: hovered ? AppColors.primaryLight.withValues(alpha: 0.5) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: hovered ? AppColors.primary : AppColors.border,
                width: 1.4,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 20, color: hovered ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 10),
                Text(
                  'Add another category',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: hovered ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.pie_chart_outline_rounded, size: 30, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'No grading categories yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Add the categories from your syllabus, such as Quizzes or Major exam, '
                'and give each one its share of the final grade.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _editCategory(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add the first category'),
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

  Future<T?> _showDialog<T>({required WidgetBuilder builder, double maxWidth = 480}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        return SafeArea(
          child: AnimatedPadding(
            duration: AppMotion.fast,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(child: builder(ctx)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeightMeter extends StatelessWidget {
  final List<GradingCategoryModel> categories;
  final double total;
  final bool balanced;
  final VoidCallback onBalance;

  const _WeightMeter({
    required this.categories,
    required this.total,
    required this.balanced,
    required this.onBalance,
  });

  Color _colorFor(GradingCategoryModel c) =>
      c.isAttendance ? AppColors.gold : AccentPalette.gradientFor(c.id).first;

  @override
  Widget build(BuildContext context) {
    final shown = total <= 0 ? 1.0 : total;
    final gap = total < 100 ? 100 - total : 0.0;
    final over = total > 100 ? total - 100 : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                balanced ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 20,
                color: balanced ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  balanced
                      ? 'Weights add up to 100%'
                      : (over > 0
                          ? 'Weights are ${_n(over)}% over 100%'
                          : '${_n(gap)}% of the grade is still unassigned'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: balanced ? AppColors.textPrimary : AppColors.warning,
                  ),
                ),
              ),
              Text(
                '${_n(total)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: balanced ? AppColors.success : AppColors.warning,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final c in categories)
                    Expanded(
                      flex: ((c.weight * 100) / shown * 1000).round().clamp(1, 1000000),
                      child: Tooltip(
                        message: '${c.name}: ${_pct(c.weight)}%',
                        child: Container(
                          color: _colorFor(c),
                          margin: const EdgeInsets.only(right: 2),
                        ),
                      ),
                    ),
                  if (gap > 0)
                    Expanded(
                      flex: (gap / shown * 1000).round().clamp(1, 1000000),
                      child: Tooltip(
                        message: 'Unassigned: ${_n(gap)}%',
                        child: Container(color: const Color(0xFFE6EBE8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final c in categories)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _colorFor(c), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${c.name}  ${_pct(c.weight)}%',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              if (gap > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: Color(0xFFE6EBE8), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Unassigned  ${_n(gap)}%',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
            ],
          ),
          if (!balanced) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Until this reaches 100%, grades are scaled to the categories that '
                    'have scores, which can read higher or lower than the syllabus.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onBalance,
                  icon: const Icon(Icons.balance_rounded, size: 17),
                  label: const Text('Split evenly'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _WeightPill extends StatelessWidget {
  final String percent;
  final Color accent;

  const _WeightPill({required this.percent, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$percent% of the final grade',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '$percent%',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const _MenuRow({required this.icon, required this.label, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: destructive ? AppColors.danger : AppColors.textSecondary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

class _DialogFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  const _DialogFrame({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 20),
                style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          body,
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }
}