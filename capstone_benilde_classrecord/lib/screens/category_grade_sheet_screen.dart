import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/assessment_model.dart';
import '../models/class_model.dart';
import '../models/grading_category_model.dart';
import '../models/score_record.dart';
import '../models/student_model.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const double _tabletBreakpoint = 760;
const double _desktopBreakpoint = 1120;
const double _passing = 75;

const Color _headerSurface = Color(0xFFF8FAF9);
const Color _gridLine = Color(0xFFEDF1EE);

String _periodLabel(GradingPeriod p) {
  switch (p) {
    case GradingPeriod.prelim:
      return 'Prelim';
    case GradingPeriod.midterm:
      return 'Midterm';
    case GradingPeriod.finals:
      return 'Finals';
  }
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);

Color _scoreColor(double? pct) =>
    pct == null ? AppColors.textMuted : (pct >= _passing ? AppColors.success : AppColors.danger);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _Metrics {
  final double nameWidth;
  final double scoreWidth;
  final double totalWidth;
  final double rowHeight;
  final double headerHeight;
  final bool showAvatar;

  const _Metrics({
    required this.nameWidth,
    required this.scoreWidth,
    required this.totalWidth,
    required this.rowHeight,
    required this.headerHeight,
    required this.showAvatar,
  });

  static const wide = _Metrics(
    nameWidth: 244,
    scoreWidth: 96,
    totalWidth: 132,
    rowHeight: 56,
    headerHeight: 64,
    showAvatar: true,
  );

  static const narrow = _Metrics(
    nameWidth: 124,
    scoreWidth: 78,
    totalWidth: 74,
    rowHeight: 54,
    headerHeight: 60,
    showAvatar: false,
  );
}

class CategoryGradeSheetScreen extends StatefulWidget {
  final ClassModel classModel;
  final GradingCategoryModel category;
  final GradingPeriod period;

  const CategoryGradeSheetScreen({
    super.key,
    required this.classModel,
    required this.category,
    required this.period,
  });

  @override
  State<CategoryGradeSheetScreen> createState() => _CategoryGradeSheetScreenState();
}

class _CategoryGradeSheetScreenState extends State<CategoryGradeSheetScreen> {

  final ScrollController _hHeader = ScrollController();
  final ScrollController _hBody = ScrollController();
  final ScrollController _vName = ScrollController();
  final ScrollController _vBody = ScrollController();
  final ScrollController _vTotal = ScrollController();
  bool _syncing = false;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _nodes = {};
  final Set<String> _justSaved = {};
  final Set<String> _overMax = {};

  bool _loading = true;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  ClassModel get _class => widget.classModel;

  late GradingCategoryModel _category;

  bool get _locked => _class.lockedFor(widget.period);

  String get _lockedMessage =>
      '${_periodLabel(widget.period)} is finalized. Reopen it on the grades page first.';

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _link([_hHeader, _hBody]);
    _link([_vName, _vBody, _vTotal]);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    _searchCtrl.dispose();
    _hHeader.dispose();
    _hBody.dispose();
    _vName.dispose();
    _vBody.dispose();
    _vTotal.dispose();
    super.dispose();
  }

  void _link(List<ScrollController> group) {
    for (final source in group) {
      source.addListener(() {
        if (_syncing || !source.hasClients) return;
        _syncing = true;
        for (final target in group) {
          if (identical(target, source) || !target.hasClients) continue;
          final pos = target.position;
          final offset = source.offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
          if (offset != target.offset) target.jumpTo(offset);
        }
        _syncing = false;
      });
    }
  }

  String _key(String studentId, String assessmentId) => '$studentId|$assessmentId';

  List<AssessmentModel> get _items => _class.assessments
      .where((a) => a.gradingPeriod == widget.period && a.categoryId == _category.id)
      .toList();

  List<GradingCategoryModel> get _sheetTabs {
    final parentIds = _class.gradingCategories
        .map((c) => c.parentId)
        .whereType<String>()
        .toSet();

    return _class.gradingCategories
        .where((c) => !c.isAttendance && !parentIds.contains(c.id))
        .toList();
  }

  String? _parentNameOf(GradingCategoryModel category) {
    if (category.parentId == null) return null;
    for (final c in _class.gradingCategories) {
      if (c.id == category.parentId) return c.name;
    }
    return null;
  }

  int _itemCountOf(GradingCategoryModel category) => _class.assessments
      .where((a) => a.gradingPeriod == widget.period && a.categoryId == category.id)
      .length;

  void _openSheet(GradingCategoryModel category) {
    if (category.id == _category.id) return;
    HapticFeedback.selectionClick();

    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }

    setState(() {
      _controllers.clear();
      _nodes.clear();
      _justSaved.clear();
      _overMax.clear();
      _searchCtrl.clear();
      _query = '';
      _category = category;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in [_hHeader, _hBody]) {
        if (c.hasClients) c.jumpTo(0);
      }
    });
  }

  ScoreRecord? _score(String studentId, String assessmentId) {
    for (final s in _class.scores) {
      if (s.studentId == studentId && s.assessmentId == assessmentId) return s;
    }
    return null;
  }

  List<StudentModel> get _students {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _class.activeStudents;
    return _class.activeStudents
        .where((s) =>
            s.name.toLowerCase().contains(q) || s.studentNumber.toLowerCase().contains(q))
        .toList();
  }

  double? _percentFor(String studentId) {
    double score = 0;
    double max = 0;
    var any = false;
    for (final a in _items) {
      final r = _score(studentId, a.id);
      if (r != null) {
        score += r.score;
        max += a.maxScore;
        any = true;
      }
    }
    if (!any || max == 0) return null;
    return score / max * 100;
  }

  double? _itemAverage(AssessmentModel a) {
    double total = 0;
    var n = 0;
    for (final s in _class.activeStudents) {
      final r = _score(s.id, a.id);
      if (r != null) {
        total += r.score;
        n++;
      }
    }
    return n == 0 ? null : total / n / a.maxScore * 100;
  }

  int _scoredCount(AssessmentModel a) =>
      _class.activeStudents.where((s) => _score(s.id, a.id) != null).length;

  TextEditingController _controllerFor(String studentId, AssessmentModel a) {
    final key = _key(studentId, a.id);
    var controller = _controllers[key];
    if (controller == null) {
      final record = _score(studentId, a.id);
      controller = TextEditingController(text: record == null ? '' : _num(record.score));
      _controllers[key] = controller;
    }
    return controller;
  }

  FocusNode _nodeFor(String key) {
    var node = _nodes[key];
    if (node == null) {
      node = FocusNode();
      node.addListener(() {
        if (mounted) setState(() {});
      });
      _nodes[key] = node;
    }
    return node;
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Couldn’t save that score. Check your connection.',
      };

  Future<void> _commit(String studentId, AssessmentModel a, String raw) async {
    if (_locked) return;
    final key = _key(studentId, a.id);
    final text = raw.trim();
    final existing = _score(studentId, a.id);

    if (text.isEmpty) {
      if (existing != null) {
        setState(() {
          _class.scores.remove(existing);
          _overMax.remove(key);
        });
        try {
          await ClassRepository.instance.saveScores(_class.id, [
            (assessmentId: a.id, enrollmentId: studentId, score: null)
          ]);
        } catch (e) {
          if (!mounted) return;
          setState(() => _class.scores.add(existing));
          _controllers[key]?.text = _num(existing.score);
          AppToast.show(context, _messageFor(e), type: ToastType.error);
        }
      }
      return;
    }

    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {

      _controllers[key]?.text = existing == null ? '' : _num(existing.score);
      AppToast.show(context, 'Enter a number between 0 and ${_num(a.maxScore)}.',
          type: ToastType.error);
      return;
    }

    setState(() {
      if (existing != null) {
        existing.score = parsed;
      } else {
        _class.scores.add(ScoreRecord(studentId: studentId, assessmentId: a.id, score: parsed));
      }
      final normalized = _num(parsed);
      if (_controllers[key]?.text != normalized && !(_nodes[key]?.hasFocus ?? false)) {
        _controllers[key]?.text = normalized;
      }
      if (parsed > a.maxScore) {
        _overMax.add(key);
      } else {
        _overMax.remove(key);
      }
      _justSaved.add(key);
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _justSaved.remove(key));
    });

    final before = existing?.score;
    try {
      await ClassRepository.instance.saveScores(_class.id, [
        (assessmentId: a.id, enrollmentId: studentId, score: parsed)
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final row = _score(studentId, a.id);
        if (row == null) return;
        if (before == null) {
          _class.scores.remove(row);
        } else {
          row.score = before;
        }
        _overMax.remove(key);
        _justSaved.remove(key);
      });
      _controllers[key]?.text = before == null ? '' : _num(before);
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  void _moveDown(int rowIndex, AssessmentModel a) {
    final students = _students;
    if (rowIndex + 1 >= students.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    final next = _key(students[rowIndex + 1].id, a.id);
    _nodeFor(next).requestFocus();
    final ctrl = _controllers[next];
    if (ctrl != null) {
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    }
  }

  Future<void> _editItem({AssessmentModel? existing}) async {
    if (_locked) {
      AppToast.show(context, _lockedMessage, type: ToastType.info);
      return;
    }
    final nameCtrl = TextEditingController(
      text: existing?.name ?? '${_category.name.replaceAll(RegExp(r's$'), '')} ${_items.length + 1}',
    );
    final maxCtrl = TextEditingController(text: existing != null ? _num(existing.maxScore) : '100');
    final formKey = GlobalKey<FormState>();

    final result = await _dialog<String>(
      maxWidth: 460,
      builder: (ctx) => _DialogFrame(
        icon: existing == null ? Icons.post_add_rounded : Icons.edit_outlined,
        title: existing == null ? 'New item in ${_category.name}' : 'Edit ${existing.name}',
        subtitle: existing == null
            ? 'It becomes a column on this sheet for ${_periodLabel(widget.period)}.'
            : null,
        body: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Give the item a name.' : null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Quiz 1',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: maxCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number.';
                  if (n <= 0) return 'Perfect score must be more than 0.';
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) Navigator.of(ctx).pop('save');
                },
                decoration: const InputDecoration(
                  labelText: 'Perfect score',
                  hintText: 'e.g. 50',
                  helperText: 'What a student gets for a perfect paper.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null) ...[
            TextButton.icon(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            ),
            const Spacer(),
          ],
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.of(ctx).pop('save');
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            child: Text(existing == null ? 'Add item' : 'Save changes'),
          ),
        ],
      ),
    );

    if (!mounted) {
      nameCtrl.dispose();
      maxCtrl.dispose();
      return;
    }

    if (result == 'delete' && existing != null) {
      await _deleteItem(existing);
    } else if (result == 'save') {
      final name = nameCtrl.text.trim();
      final max = double.tryParse(maxCtrl.text.trim()) ?? 100;

      try {
        if (existing != null) {
          final updated = AssessmentModel(
            id: existing.id,
            name: name,
            categoryId: _category.id,
            gradingPeriod: widget.period,
            maxScore: max,
          );
          await ClassRepository.instance.updateAssessment(updated);
          final i = _class.assessments.indexOf(existing);
          if (mounted && i >= 0) setState(() => _class.assessments[i] = updated);
        } else {

          final created = await ClassRepository.instance.createAssessment(
            _category.id,
            name: name,
            maxScore: max,
            period: widget.period,
          );
          if (mounted) {
            setState(() => _class.assessments.add(created));
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
          }
        }

        if (!mounted) return;
        AppToast.show(context, existing == null ? 'Added $name' : 'Saved $name',
            type: ToastType.success);
      } catch (e) {
        if (mounted) AppToast.show(context, _messageFor(e), type: ToastType.error);
      }
    }
    nameCtrl.dispose();
    maxCtrl.dispose();
  }

  Future<void> _deleteItem(AssessmentModel a) async {
    final scored = _scoredCount(a);
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${a.name}?',
      message: scored == 0
          ? 'No scores are recorded for it yet, so nothing else changes.'
          : 'This also deletes $scored recorded score${scored == 1 ? '' : 's'}. '
              'Every student’s ${_category.name} percentage is recalculated without it.',
      confirmLabel: 'Delete item',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    try {
      await ClassRepository.instance.deleteAssessment(a.id);
    } catch (e) {
      if (mounted) AppToast.show(context, _messageFor(e), type: ToastType.error);
      return;
    }
    if (!mounted) return;

    setState(() {
      _class.assessments.remove(a);
      _class.scores.removeWhere((s) => s.assessmentId == a.id);

      final suffix = '|${a.id}';
      _overMax.removeWhere((k) => k.endsWith(suffix));
      _justSaved.removeWhere((k) => k.endsWith(suffix));
      for (final k in _controllers.keys.where((k) => k.endsWith(suffix)).toList()) {
        _controllers.remove(k)?.dispose();
        _nodes.remove(k)?.dispose();
      }
    });

    AppToast.show(context, 'Deleted ${a.name}');
  }

  Future<void> _addMultiple() async {
    if (_locked) {
      AppToast.show(context, _lockedMessage, type: ToastType.info);
      return;
    }
    final base = _category.name.replaceAll(RegExp(r's$'), '');
    final prefixCtrl = TextEditingController(text: base);
    final countCtrl = TextEditingController(text: '4');
    final maxCtrl = TextEditingController(text: '100');
    final formKey = GlobalKey<FormState>();
    final start = _items.length + 1;

    final ok = await _dialog<bool>(
      maxWidth: 480,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final count = int.tryParse(countCtrl.text.trim()) ?? 0;
        final preview = count <= 0
            ? '—'
            : List.generate(math.min(count, 3), (i) => '${prefixCtrl.text.trim()} ${start + i}')
                    .join(', ') +
                (count > 3 ? ', … ${prefixCtrl.text.trim()} ${start + count - 1}' : '');

        return _DialogFrame(
          icon: Icons.playlist_add_rounded,
          title: 'Add several items at once',
          subtitle: 'Numbered in sequence, all with the same perfect score.',
          body: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: prefixCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setLocal(() {}),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Quiz'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: countCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setLocal(() {}),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'At least 1.';
                          if (n > 50) return 'At most 50.';
                          return null;
                        },
                        decoration: const InputDecoration(labelText: 'How many'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: maxCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'More than 0.';
                          return null;
                        },
                        decoration: const InputDecoration(labelText: 'Perfect score'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This creates',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
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
                if (formKey.currentState?.validate() ?? false) Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              child: const Text('Add items'),
            ),
          ],
        );
      }),
    );

    if (ok == true && mounted) {
      final prefix = prefixCtrl.text.trim();
      final count = int.tryParse(countCtrl.text.trim()) ?? 0;
      final max = double.tryParse(maxCtrl.text.trim()) ?? 100;
      try {

        final added = await ClassRepository.instance.createAssessmentSeries(
          _category.id,
          namePrefix: prefix,
          count: count,
          maxScore: max,
          period: widget.period,
        );
        if (mounted) {
          setState(() => _class.assessments.addAll(added));
          AppToast.show(
            context,
            'Added ${added.length} item${added.length == 1 ? '' : 's'}',
            type: ToastType.success,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
        }
      } catch (e) {
        if (mounted) AppToast.show(context, _messageFor(e), type: ToastType.error);
      }
    }
    prefixCtrl.dispose();
    countCtrl.dispose();
    maxCtrl.dispose();
  }

  void _scrollToEnd() {
    if (!_hBody.hasClients) return;
    _hBody.animateTo(
      _hBody.position.maxScrollExtent,
      duration: const Duration(milliseconds: 380),
      curve: AppMotion.curve,
    );
  }

  Future<T?> _dialog<T>({required WidgetBuilder builder, double maxWidth = 480}) {
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = width >= _tabletBreakpoint;
    final desktop = width >= _desktopBreakpoint;
    final hPad = desktop ? 32.0 : (tablet ? 24.0 : 12.0);
    final items = _items;
    final hasSheet = _class.activeStudents.isNotEmpty && items.isNotEmpty;

    return Scaffold(
      appBar: _appBar(tablet),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, tablet ? 18 : 12, hPad, tablet ? 24 : 12),
              child: LayoutBuilder(builder: (context, c) {
                final roomy = c.maxHeight >= 560;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tablet) _breadcrumb(),
                    if (_locked) ...[
                      SizedBox(height: tablet ? 14 : 8),
                      _LockedSheetBanner(period: _periodLabel(widget.period)),
                    ],
                    if (hasSheet && roomy) ...[
                      SizedBox(height: tablet ? 14 : 0),
                      _loading ? _StatsSkeleton(compact: !tablet) : _stats(items, tablet),
                    ],
                    if (hasSheet) ...[
                      SizedBox(height: tablet ? 14 : 10),
                      _toolbar(tablet),
                    ],
                    SizedBox(height: tablet ? 14 : 10),
                    Expanded(child: _sheetCard(items, tablet, desktop)),

                    if (_sheetTabs.length > 1) ...[
                      SizedBox(height: tablet ? 10 : 8),
                      _SheetTabs(
                        tabs: [
                          for (final c in _sheetTabs)
                            (
                              category: c,
                              parentName: _parentNameOf(c),
                              itemCount: _itemCountOf(c),
                              locked: _class.lockedFor(widget.period),
                            ),
                        ],
                        currentId: _category.id,
                        onSelect: _openSheet,
                      ),
                    ],
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool tablet) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back to gradebook',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 4,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _category.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
          Text(
            '${_periodLabel(widget.period)}  ${_class.subjectName}',
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
        if (_locked) ...[
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: _FinalizedChip(),
          ),
        ] else ...[

          if (!tablet) ...[
            IconButton(
              icon: const Icon(Icons.playlist_add_rounded),
              tooltip: 'Add several items',
              onPressed: _addMultiple,
            ),
            const SizedBox(width: 4),
          ],
          if (tablet)
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: ElevatedButton.icon(
                onPressed: () => _editItem(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add item'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            )
          else ...[
            IconButton.filled(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add item',
              onPressed: () => _editItem(),
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
      ],
    );
  }

  Widget _breadcrumb() {
    return Row(
      children: [
        Flexible(
          child: Hoverable(
            builder: (context, hovered) => GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Text(
                'Gradebook',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hovered ? AppColors.primary : AppColors.textMuted,
                  decoration: hovered ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
        ),
        Flexible(
          child: Text(
            '${_category.name}, ${_periodLabel(widget.period)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stats(List<AssessmentModel> items, bool tablet) {
    final percents = _class.activeStudents.map((s) => _percentFor(s.id)).whereType<double>().toList();
    final avg = percents.isEmpty ? null : percents.reduce((a, b) => a + b) / percents.length;
    final cells = items.length * _class.activeStudents.length;
    final filled = items.fold<int>(0, (sum, a) => sum + _scoredCount(a));
    final below = percents.where((p) => p < _passing).length;
    final totalPoints = items.fold<double>(0, (s, a) => s + a.maxScore);

    final tiles = <Widget>[
      _StatTile(
        icon: Icons.layers_outlined,
        color: AppColors.primary,
        background: AppColors.primaryLight,
        label: 'Items',
        value: '${items.length}',
        caption: '${_num(totalPoints)} points in total',
        compact: !tablet,
      ),
      _StatTile(
        icon: Icons.insights_rounded,
        color: avg == null ? AppColors.textMuted : _scoreColor(avg),
        background: avg == null
            ? AppColors.background
            : (avg >= _passing ? AppColors.successBg : AppColors.dangerBg),
        label: 'Class average',
        value: avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
        caption: avg == null ? 'No scores yet' : 'Across ${percents.length} students',
        progress: avg == null ? null : avg / 100,
        compact: !tablet,
      ),
      _StatTile(
        icon: Icons.edit_note_rounded,
        color: AppColors.goldDark,
        background: AppColors.goldLight,
        label: 'Scores entered',
        value: cells == 0 ? '—' : '$filled/$cells',
        caption: filled == cells && cells > 0 ? 'This sheet is complete' : 'Empty cells are not counted',
        compact: !tablet,
      ),
      _StatTile(
        icon: below == 0 ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
        color: below == 0 ? AppColors.success : AppColors.danger,
        background: below == 0 ? AppColors.successBg : AppColors.dangerBg,
        label: 'Below ${_passing.toStringAsFixed(0)}%',
        value: percents.isEmpty ? '—' : '$below',
        caption: percents.isEmpty
            ? 'Shows once scores are in'
            : (below == 0 ? 'Everyone is passing here' : 'In this category'),
        compact: !tablet,
      ),
    ];

    if (tablet) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(width: 176, child: tiles[i]),
      ),
    );
  }

  Widget _toolbar(bool tablet) {
    final search = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'Search by name or student no.',
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          suffixIcon: _query.isEmpty
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
    );

    return Row(
      children: [
        if (tablet)
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: search)
        else
          Expanded(child: search),
        if (tablet && !_locked) ...[
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _addMultiple,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('Add several'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sheetCard(List<AssessmentModel> items, bool tablet, bool desktop) {
    final m = tablet ? _Metrics.wide : _Metrics.narrow;
    Widget child;

    if (_loading) {
      child = _GridSkeleton(metrics: m);
    } else if (_class.activeStudents.isEmpty) {
      child = _EmptyState(
        icon: Icons.group_add_outlined,
        title: 'No students in this class yet',
        message: 'Add students from the class page, then come back to record scores.',
        primaryLabel: 'Back to class',
        primaryIcon: Icons.arrow_back_rounded,
        onPrimary: () => Navigator.of(context).maybePop(),
      );
    } else if (items.isEmpty && _locked) {
      child = _EmptyState(
        icon: Icons.lock_outline_rounded,
        title: '${_periodLabel(widget.period)} is finalized',
        message: 'No ${_category.name.toLowerCase()} were recorded in this period, and it can no '
            'longer be changed. Reopen the period on the grades page if this was a mistake.',
        primaryLabel: 'Back to class',
        primaryIcon: Icons.arrow_back_rounded,
        onPrimary: () => Navigator.of(context).maybePop(),
      );
    } else if (items.isEmpty) {
      child = _NoItemsState(
        category: _category.name,
        period: _periodLabel(widget.period),
        wide: tablet,
        onAddOne: () => _editItem(),
        onAddMany: _addMultiple,
      );
    } else {
      final students = _students;
      if (students.isEmpty) {
        child = _EmptyState(
          icon: Icons.person_search_outlined,
          title: 'No students match “${_query.trim()}”',
          message: 'Check the spelling, or search by student number instead.',
          primaryLabel: 'Clear search',
          primaryIcon: Icons.filter_alt_off_outlined,
          onPrimary: () {
            _searchCtrl.clear();
            setState(() => _query = '');
          },
        );
      } else {
        child = _grid(students, items, m, desktop);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _grid(
    List<StudentModel> students,
    List<AssessmentModel> items,
    _Metrics m,
    bool desktop,
  ) {
    final noBars = ScrollConfiguration.of(context).copyWith(scrollbars: false);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final mid = math.max(0.0, c.maxWidth - m.nameWidth - m.totalWidth);
            final contentWidth = math.max(items.length * m.scoreWidth, mid);

            return Column(
              children: [

                SizedBox(
                  height: m.headerHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cornerCell(students.length, m),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: noBars,
                          child: SingleChildScrollView(
                            controller: _hHeader,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: contentWidth,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final a in items)
                                    _ItemHeaderCell(
                                      item: a,
                                      width: m.scoreWidth,
                                      scored: _scoredCount(a),
                                      totalStudents: _class.activeStudents.length,
                                      average: _itemAverage(a),
                                      onTap: _locked ? null : () => _editItem(existing: a),
                                    ),
                                  const Expanded(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: _headerSurface,
                                        border: Border(bottom: BorderSide(color: AppColors.border)),
                                      ),
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _totalHeader(m),
                    ],
                  ),
                ),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: m.nameWidth,
                        child: ScrollConfiguration(
                          behavior: noBars,
                          child: ListView.builder(
                            controller: _vName,
                            physics: const ClampingScrollPhysics(),
                            itemExtent: m.rowHeight,
                            itemCount: students.length,
                            itemBuilder: (_, i) => _nameCell(students[i], m),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _hBody,
                          thumbVisibility: desktop,
                          child: ScrollConfiguration(
                            behavior: noBars,
                            child: SingleChildScrollView(
                              controller: _hBody,
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: SizedBox(
                                width: contentWidth,
                                child: ListView.builder(
                                  controller: _vBody,
                                  physics: const ClampingScrollPhysics(),
                                  itemExtent: m.rowHeight,
                                  itemCount: students.length,
                                  itemBuilder: (_, row) {
                                    final s = students[row];
                                    return DecoratedBox(
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: _gridLine)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          for (final a in items)
                                            _scoreCell(s, a, row, m),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: m.totalWidth,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: AppColors.border)),
                          ),
                          child: ScrollConfiguration(
                            behavior: noBars,
                            child: ListView.builder(
                              controller: _vTotal,
                              physics: const ClampingScrollPhysics(),
                              itemExtent: m.rowHeight,
                              itemCount: students.length,
                              itemBuilder: (_, i) =>
                                  _TotalCell(percent: _percentFor(students[i].id), metrics: m),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        _footer(desktop),
      ],
    );
  }

  Widget _cornerCell(int count, _Metrics m) {
    return Container(
      width: m.nameWidth,
      padding: EdgeInsets.symmetric(horizontal: m.showAvatar ? 18 : 12),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'Student',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalHeader(_Metrics m) {
    return Container(
      width: m.totalWidth,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(
          left: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Tooltip(
        message: 'Total across the items this student has scores for',
        child: Text(
          m.showAvatar ? '${_category.name} %' : '%',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _nameCell(StudentModel s, _Metrics m) {
    final pct = _percentFor(s.id);
    final low = pct != null && pct < _passing;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.showAvatar ? 16 : 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: _gridLine),
        ),
      ),
      child: Row(
        children: [
          if (m.showAvatar) ...[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Text(
                _initials(s.name),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.showAvatar ? 14 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (low && !m.showAvatar) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger),
                    ],
                  ],
                ),
                if (s.studentNumber.isNotEmpty)
                  Text(
                    s.studentNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCell(StudentModel s, AssessmentModel a, int row, _Metrics m) {
    final key = _key(s.id, a.id);
    final controller = _controllerFor(s.id, a);
    final node = _nodeFor(key);
    final saved = _justSaved.contains(key);
    final over = _overMax.contains(key);
    final record = _score(s.id, a.id);
    final ratio = record == null || a.maxScore == 0 ? null : record.score / a.maxScore * 100;

    final Color borderColor;
    if (over) {
      borderColor = AppColors.danger;
    } else if (saved) {
      borderColor = AppColors.success;
    } else if (node.hasFocus) {
      borderColor = AppColors.primary;
    } else {
      borderColor = AppColors.border;
    }

    return Container(
      width: m.scoreWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _gridLine)),
      ),
      child: Tooltip(
        message: over
            ? '${_num(record!.score)} is above the perfect score of ${_num(a.maxScore)}'
            : (record == null
                ? '${s.name}, ${a.name}: not scored'
                : '${s.name}, ${a.name}: ${_num(record.score)} of ${_num(a.maxScore)}'),
        waitDuration: const Duration(milliseconds: 600),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: over
                ? AppColors.dangerBg
                : (saved
                    ? AppColors.successBg
                    : (record == null ? AppColors.background : AppColors.surface)),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: borderColor,
              width: over || saved || node.hasFocus ? 1.6 : 1.2,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: node,
            readOnly: _locked,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: over
                  ? AppColors.danger
                  : (record == null ? AppColors.textMuted : _scoreColor(ratio)),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: '–',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            ),
            onTap: () => controller.selection =
                TextSelection(baseOffset: 0, extentOffset: controller.text.length),
            onSubmitted: (v) {
              _commit(s.id, a, v);
              _moveDown(row, a);
            },
            onEditingComplete: () {},
            onTapOutside: (_) {
              if (node.hasFocus) {
                _commit(s.id, a, controller.text);
                node.unfocus();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _footer(bool desktop) {
    final overCount = _overMax.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            _locked
                ? '${_periodLabel(widget.period)} is finalized, so this sheet is read-only. '
                    'Reopen the period on the grades page to change anything.'
                : (desktop
                    ? 'Type a score and press Enter to move to the next student. Click a column header to rename it. '
                        'A blank cell is not counted yet; type 0 if the student missed it.'
                    : 'Tap a cell to type a score. Tap a column header to rename it. '
                        'A blank cell is not counted yet; type 0 if the student missed it.'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          if (overCount > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(
                  '$overCount score${overCount == 1 ? '' : 's'} above the perfect score',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ],
            )
          else
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done_outlined, size: 15, color: AppColors.success),
                SizedBox(width: 6),
                Text(
                  'Changes save automatically',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ItemHeaderCell extends StatelessWidget {
  final AssessmentModel item;
  final double width;
  final int scored;
  final int totalStudents;
  final double? average;
  final VoidCallback? onTap;

  const _ItemHeaderCell({
    required this.item,
    required this.width,
    required this.scored,
    required this.totalStudents,
    required this.average,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final complete = totalStudents > 0 && scored == totalStudents;
    return Tooltip(
      message: average == null
          ? '${item.name}, out of ${_num(item.maxScore)}. No scores yet.'
          : '${item.name}, out of ${_num(item.maxScore)}. '
              'Average ${average!.toStringAsFixed(1)}%, $scored of $totalStudents scored.',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: _headerSurface,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.primary.withValues(alpha: 0.06),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: _gridLine),
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'out of ${_num(item.maxScore)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: AppMotion.base,
                      curve: AppMotion.curve,
                      height: 2,
                      width: totalStudents == 0 ? 0 : width * (scored / totalStudents),
                      color: complete
                          ? AppColors.success.withValues(alpha: 0.7)
                          : AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  final double? percent;
  final _Metrics metrics;

  const _TotalCell({required this.percent, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final v = percent;
    final text = Text(
      v == null ? '—' : '${v.toStringAsFixed(1)}%',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: _scoreColor(v),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.showAvatar ? 14 : 8),
      alignment: metrics.showAvatar ? Alignment.center : Alignment.centerRight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: _gridLine)),
      ),
      child: !metrics.showAvatar
          ? text
          : Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Stack(
                      children: [
                        Container(height: 6, color: _gridLine),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ((v ?? 0) / 100).clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            color: v == null ? Colors.transparent : _scoreColor(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 48, child: text),
              ],
            ),
    );
  }
}

class _NoItemsState extends StatelessWidget {
  final String category;
  final String period;
  final bool wide;
  final VoidCallback onAddOne;
  final VoidCallback onAddMany;

  const _NoItemsState({
    required this.category,
    required this.period,
    required this.wide,
    required this.onAddOne,
    required this.onAddMany,
  });

  @override
  Widget build(BuildContext context) {
    final one = _OptionCard(
      icon: Icons.add_rounded,
      title: 'Add one item',
      description: 'Name it and set its perfect score',
      recommended: true,
      onTap: onAddOne,
    );
    final many = _OptionCard(
      icon: Icons.playlist_add_rounded,
      title: 'Add several at once',
      description: 'Numbered in sequence, same perfect score',
      onTap: onAddMany,
    );

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetGlyph(),
              const SizedBox(height: 22),
              Text(
                'No $category in $period yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: wide ? 22 : 19),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  'Each item you add becomes a column here, with one cell per student. '
                  'Scores save as you type them.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: one),
                      const SizedBox(width: 12),
                      Expanded(child: many),
                    ],
                  ),
                )
              else ...[
                one,
                const SizedBox(height: 10),
                many,
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 260.ms);
  }
}

class _SheetGlyph extends StatelessWidget {
  const _SheetGlyph();

  @override
  Widget build(BuildContext context) {
    const rows = 4;
    const cols = 3;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 12,
                  decoration: BoxDecoration(
                    color: r == 0 ? AppColors.textMuted.withValues(alpha: 0.35) : AppColors.background,
                    borderRadius: BorderRadius.circular(3),
                    border: r == 0 ? null : Border.all(color: AppColors.border),
                  ),
                ),
                for (var c = 0; c < cols; c++) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 22,
                    height: 12,
                    decoration: BoxDecoration(
                      color: r == 0 ? AppColors.primary : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: (200 + c * 140 + r * 40).ms, duration: 240.ms)
                      .scale(begin: const Offset(0.4, 1), curve: Curves.easeOutBack),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool recommended;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: recommended ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: recommended
                ? AppColors.primary
                : (hovered ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
            width: 1.3,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: recommended
                          ? Colors.white.withValues(alpha: 0.16)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 21, color: recommended ? Colors.white : AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: recommended ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: recommended
                                ? Colors.white.withValues(alpha: 0.82)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSlide(
                    duration: AppMotion.fast,
                    offset: Offset(hovered ? 0.15 : 0, 0),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: recommended ? Colors.white : AppColors.textMuted,
                    ),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onPrimary,
                icon: Icon(primaryIcon, size: 18),
                label: Text(primaryLabel),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 240.ms);
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String label;
  final String value;
  final String caption;
  final double? progress;
  final bool compact;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
    required this.value,
    required this.caption,
    this.progress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  height: 1.1,
                  color: progress != null ? color : AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 550),
                curve: AppMotion.curve,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  color: color,
                  backgroundColor: _gridLine,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            caption,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  final bool compact;

  const _StatsSkeleton({required this.compact});

  @override
  Widget build(BuildContext context) {
    Widget tile() => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 110, height: 14),
              SizedBox(height: 14),
              SkeletonBox(width: 64, height: 22),
              SizedBox(height: 10),
              SkeletonBox(width: 120, height: 11),
            ],
          ),
        );
    if (compact) {
      return SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, _) => SizedBox(width: 176, child: tile()),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tile()),
        ],
      ],
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  final _Metrics metrics;

  const _GridSkeleton({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: metrics.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: _headerSurface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: metrics.nameWidth - 32,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: 80, height: 14),
                ),
              ),
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Row(
                      children: [
                        for (var i = 0; i < 10; i++)
                          SizedBox(
                            width: metrics.scoreWidth,
                            child: const Center(child: SkeletonBox(width: 56, height: 24, radius: 6)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            itemExtent: metrics.rowHeight,
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _gridLine)),
              ),
              child: Row(
                children: [
                  if (metrics.showAvatar) ...[
                    const SkeletonBox(width: 34, height: 34, radius: 17),
                    const SizedBox(width: 12),
                  ],
                  SkeletonBox(width: metrics.showAvatar ? 150.0 - (i % 3) * 22 : 80, height: 13),
                  const Spacer(),
                  SkeletonBox(width: metrics.showAvatar ? 90 : 36, height: 10),
                ],
              ),
            ),
          ),
        ),
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

class _FinalizedChip extends StatelessWidget {
  const _FinalizedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.warning),
          SizedBox(width: 6),
          Text(
            'Finalized',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedSheetBanner extends StatelessWidget {
  final String period;

  const _LockedSheetBanner({required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$period is finalized, so this sheet is read-only. Reopen the period from the '
              'grades page if you still need to change a score or an item.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SheetTab = ({
  GradingCategoryModel category,
  String? parentName,
  int itemCount,
  bool locked,
});

class _SheetTabs extends StatefulWidget {
  final List<_SheetTab> tabs;
  final String currentId;
  final ValueChanged<GradingCategoryModel> onSelect;

  const _SheetTabs({
    required this.tabs,
    required this.currentId,
    required this.onSelect,
  });

  @override
  State<_SheetTabs> createState() => _SheetTabsState();
}

class _SheetTabsState extends State<_SheetTabs> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void didUpdateWidget(covariant _SheetTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentId != widget.currentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    final key = _keys[widget.currentId];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: AppMotion.base,
      curve: AppMotion.curve,
      alignment: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, right: 2),
            child: Icon(Icons.table_chart_outlined, size: 17, color: AppColors.textMuted),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Row(
                children: [
                  for (final tab in widget.tabs) ...[
                    if (tab != widget.tabs.first) const SizedBox(width: 6),
                    _SheetTabButton(
                      key: _keys.putIfAbsent(tab.category.id, () => GlobalKey()),
                      tab: tab,
                      selected: tab.category.id == widget.currentId,
                      onTap: () => widget.onSelect(tab.category),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTabButton extends StatelessWidget {
  final _SheetTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _SheetTabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final parent = tab.parentName;
    final empty = tab.itemCount == 0;

    return Semantics(
      button: true,
      selected: selected,
      label: '${tab.category.name} sheet',
      child: Tooltip(
        message: empty
            ? '${tab.category.name}: no items yet'
            : '${tab.category.name}: ${tab.itemCount} '
                'item${tab.itemCount == 1 ? '' : 's'}',
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            hoverColor: AppColors.primary.withValues(alpha: 0.06),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.5 : 1.1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.locked) ...[
                    const Icon(Icons.lock_outline_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 5),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tab.category.name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          height: 1.2,
                          color: selected ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                      if (parent != null)
                        Text(
                          parent,
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.25,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 7),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: empty
                          ? AppColors.background
                          : (selected ? AppColors.primary : AppColors.background),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: empty ? AppColors.border : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      '${tab.itemCount}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: empty
                            ? AppColors.textMuted
                            : (selected ? Colors.white : AppColors.textSecondary),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
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