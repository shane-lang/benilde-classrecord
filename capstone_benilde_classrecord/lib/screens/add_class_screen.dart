import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/class_model.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class AddClassScreen extends StatefulWidget {

  final ClassModel? existing;

  const AddClassScreen({super.key, this.existing});

  @override
  State<AddClassScreen> createState() => _AddClassScreenState();
}

class _AddClassScreenState extends State<AddClassScreen> {
  static const double _wideBreakpoint = 980;

  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _subjectCodeController = TextEditingController();
  final _courseController = TextEditingController();
  final _yearSectionController = TextEditingController();
  final _schoolYearController = TextEditingController();

  static const List<String> _courseOptions = ['BSIT', 'CIMT'];
  static const List<String> _sectionSuggestions = ['1A', '1B', '2A', '3A', '4A'];

  static List<String> get _schoolYearSuggestions {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    return [
      '${start - 1}-$start',
      '$start-${start + 1}',
      '${start + 1}-${start + 2}',
    ];
  }

  final _prelimWeightController = TextEditingController();
  final _midtermWeightController = TextEditingController();
  final _finalsWeightController = TextEditingController();
  bool _customPeriodWeights = false;

  bool _saving = false;
  bool _dirty = false;

  bool get _editing => widget.existing != null;

  List<String> get _courseChoices {
    final current = widget.existing?.course.trim().toUpperCase() ?? '';
    return [
      ..._courseOptions,
      if (current.isNotEmpty && !_courseOptions.contains(current)) current,
    ];
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _subjectController.text = existing.subjectName;
      _subjectCodeController.text = existing.subjectCode;
      _courseController.text = existing.course;
      _yearSectionController.text = existing.yearSection;
      _schoolYearController.text = existing.schoolYear;
      _customPeriodWeights = existing.hasPeriodWeights;
      if (_customPeriodWeights) {
        _prelimWeightController.text = _pct(existing.prelimWeight);
        _midtermWeightController.text = _pct(existing.midtermWeight);
        _finalsWeightController.text = _pct(existing.finalsWeight);
      }
    }
    if (!_customPeriodWeights) {
      _prelimWeightController.text = '30';
      _midtermWeightController.text = '30';
      _finalsWeightController.text = '40';
    }
    for (final c in [
      _subjectController,
      _subjectCodeController,
      _courseController,
      _yearSectionController,
      _schoolYearController,
      _prelimWeightController,
      _midtermWeightController,
      _finalsWeightController,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _subjectCodeController.dispose();
    _courseController.dispose();
    _yearSectionController.dispose();
    _schoolYearController.dispose();
    _prelimWeightController.dispose();
    _midtermWeightController.dispose();
    _finalsWeightController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final existing = widget.existing;
    final bool changed;
    if (existing != null) {

      changed = _subjectController.text.trim() != existing.subjectName ||
          _subjectCodeController.text.trim() != existing.subjectCode ||
          _courseController.text.trim() != existing.course ||
          _yearSectionController.text.trim() != existing.yearSection ||
          _schoolYearController.text.trim() != existing.schoolYear ||
          _customPeriodWeights != existing.hasPeriodWeights ||
          (_customPeriodWeights &&
              (_weight(_prelimWeightController) != existing.prelimWeight ||
                  _weight(_midtermWeightController) != existing.midtermWeight ||
                  _weight(_finalsWeightController) != existing.finalsWeight));
    } else {
      changed = _subjectController.text.isNotEmpty ||
          _subjectCodeController.text.isNotEmpty ||
          _courseController.text.isNotEmpty ||
          _yearSectionController.text.isNotEmpty ||
          _schoolYearController.text.isNotEmpty;
    }

    setState(() => _dirty = changed);
  }

  bool get _isComplete =>
      _subjectController.text.trim().isNotEmpty &&
      _subjectCodeController.text.trim().isNotEmpty &&
      _courseController.text.trim().isNotEmpty &&
      _yearSectionController.text.trim().isNotEmpty &&
      _schoolYearController.text.trim().isNotEmpty;

  static String _pct(double fraction) {
    final value = fraction * 100;
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(2);
  }

  double _weight(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll('%', ''));
    return v == null ? 0 : v / 100;
  }

  double get _periodWeightTotal =>
      (_weight(_prelimWeightController) +
              _weight(_midtermWeightController) +
              _weight(_finalsWeightController)) *
          100;

  Future<void> _save() async {

    if (!_formKey.currentState!.validate()) {
      AppToast.show(
        context,
        'Please complete the highlighted fields.',
        type: ToastType.error,
      );
      return;
    }

    if (_customPeriodWeights && (_periodWeightTotal - 100).abs() > 0.01) {
      AppToast.show(
        context,
        'The Prelim, Midterm and Finals weights must add up to 100%.',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _saving = true);

    final existing = widget.existing;
    final draft = ClassModel(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      subjectName: _subjectController.text.trim(),
      subjectCode: _subjectCodeController.text.trim(),
      course: _courseController.text.trim(),
      yearSection: _yearSectionController.text.trim(),
      schoolYear: _schoolYearController.text.trim(),
      studentCount: existing?.studentCount ?? 0,
      hasSchedule: existing?.hasSchedule ?? false,
      prelimWeight: _customPeriodWeights ? _weight(_prelimWeightController) : 0,
      midtermWeight: _customPeriodWeights ? _weight(_midtermWeightController) : 0,
      finalsWeight: _customPeriodWeights ? _weight(_finalsWeightController) : 0,
      createdAt: existing?.createdAt,
    );

    Navigator.of(context).pop(draft);
  }

  Future<void> _confirmDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showConfirmDialog(
      context,
      title: _editing ? 'Discard your changes?' : 'Discard this class?',
      message: _editing
          ? 'The class will keep its current details.'
          : 'The details you entered will not be saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= _wideBreakpoint;

            return Column(
              children: [
                _Header(onBack: _confirmDiscard, editing: _editing),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 32 : 18,
                      isWide ? 28 : 20,
                      isWide ? 32 : 18,
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 6, child: _buildForm()),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 4, child: _buildSideRail()),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildForm(),
                                  const SizedBox(height: 20),
                                  _buildSideRail(),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                _ActionBar(
                  saving: _saving,
                  complete: _isComplete,
                  editing: _editing,
                  onCancel: _confirmDiscard,
                  onSave: _save,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle(
                  step: '1',
                  title: 'Subject',
                  subtitle: 'What are you teaching?',
                ),
                const SizedBox(height: 20),
                _Field(
                  label: 'Subject name',
                  child: TextFormField(
                    controller: _subjectController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Computer Programming 2',
                      prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
                      counterText: '',
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Enter the subject name.';
                      if (v.length < 3) return 'Use at least 3 characters.';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'Subject code',
                  helper: 'Shown as the short label on the class card.',
                  child: TextFormField(
                    controller: _subjectCodeController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    maxLength: 12,
                    inputFormatters: [UpperCaseFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'e.g. CC102',
                      prefixIcon: Icon(Icons.tag_rounded, size: 20),
                      counterText: '',
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Enter the subject code.';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle(
                  step: '2',
                  title: 'Class',
                  subtitle: 'Who is taking it?',
                ),
                const SizedBox(height: 20),
                _Field(
                  label: 'Course',
                  child: FormField<String>(
                    validator: (_) => _courseController.text.trim().isEmpty
                        ? 'Choose the course.'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuickPicks(
                          values: _courseChoices,
                          selected: _courseController.text.trim().toUpperCase(),
                          onPick: (value) {
                            _courseController.text = value;
                            field.didChange(value);
                          },
                        ),
                        if (field.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Text(
                              field.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'Year & section',
                  child: TextFormField(
                    controller: _yearSectionController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    maxLength: 12,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 3A',
                      prefixIcon: Icon(Icons.groups_outlined, size: 20),
                      counterText: '',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter the year & section.'
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                _QuickPicks(
                  values: _sectionSuggestions,
                  selected: _yearSectionController.text.trim().toUpperCase(),
                  onPick: (value) => _yearSectionController.text = value,
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'School year',
                  child: TextFormField(
                    controller: _schoolYearController,
                    textInputAction: TextInputAction.done,
                    maxLength: 12,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 2026-2027',
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                      counterText: '',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter the school year.'
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                _QuickPicks(
                  values: _schoolYearSuggestions,
                  selected: _schoolYearController.text.trim(),
                  onPick: (value) => _schoolYearController.text = value,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _periodWeightCard(),
        ],
      ),
    );
  }

  Widget _periodWeightCard() {
    final total = _periodWeightTotal;
    final balanced = (total - 100).abs() <= 0.01;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            step: '3',
            title: 'Final grade',
            subtitle: 'How the three periods are combined',
          ),
          const SizedBox(height: 16),
          _WeightChoice(
            label: 'Equal',
            description:
                'The final grade is the average of Prelim, Midterm and Finals.',
            selected: !_customPeriodWeights,
            onTap: () {
              setState(() => _customPeriodWeights = false);
              _onFieldChanged();
            },
          ),
          const SizedBox(height: 10),
          _WeightChoice(
            label: 'Custom weights',
            description:
                'Each period carries its own percentage, for example 30% – 30% – 40%.',
            selected: _customPeriodWeights,
            onTap: () {
              setState(() => _customPeriodWeights = true);
              _onFieldChanged();
            },
          ),
          if (_customPeriodWeights) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _weightField('Prelim %', _prelimWeightController)),
                const SizedBox(width: 12),
                Expanded(child: _weightField('Midterm %', _midtermWeightController)),
                const SizedBox(width: 12),
                Expanded(child: _weightField('Finals %', _finalsWeightController)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  balanced ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                  size: 18,
                  color: balanced ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    balanced
                        ? 'Total: 100%. Ready to save.'
                        : 'Total: ${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 2)}%. '
                            'The three must add up to 100%.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: balanced ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'A period with no grade yet is left out, and the remaining weights are '
            'shared out between the periods that do have one.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _weightField(String label, TextEditingController controller) {
    return _Field(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        maxLength: 6,
        decoration: const InputDecoration(
          hintText: 'e.g. 30',
          counterText: '',
        ),
        validator: (value) {
          if (!_customPeriodWeights) return null;
          final v = double.tryParse((value ?? '').trim().replaceAll('%', ''));
          if (v == null) return 'Enter a number.';
          if (v < 0 || v > 100) return '0 to 100 only.';
          return null;
        },
      ),
    );
  }

  Widget _buildSideRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewCard(
          subjectName: _subjectController.text.trim(),
          subjectCode: _subjectCodeController.text.trim(),
          course: _courseController.text.trim(),
          yearSection: _yearSectionController.text.trim(),
        ),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: AppColors.goldDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'What happens next',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _NextStep(
                icon: Icons.person_add_alt_rounded,
                title: 'Add your students',
                body: 'Enroll names and student numbers inside the class.',
              ),
              const _NextStep(
                icon: Icons.calendar_month_rounded,
                title: 'Set the schedule',
                body: 'Meeting days and grading period dates.',
              ),
              const _NextStep(
                icon: Icons.grade_rounded,
                title: 'Configure grading',
                body: 'Adjust category weights to match your syllabus.',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final bool editing;

  const _Header({required this.onBack, this.editing = false});

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
          padding: const EdgeInsets.fromLTRB(8, 10, 18, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to my classes',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'My classes',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            editing ? 'Edit class' : 'New class',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      editing ? 'Edit class' : 'Create a class',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool saving;
  final bool complete;
  final bool editing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _ActionBar({
    required this.saving,
    required this.complete,
    this.editing = false,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1.2),
        ),
        boxShadow: AppShadows.card,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Row(
                children: [

                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          complete
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 17,
                          color: complete
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            complete
                                ? 'Ready to save'
                                : 'All four fields are required',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: complete
                                  ? AppColors.success
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: saving ? null : onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: saving ? null : onSave,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(148, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: saving
                          ? const Row(
                              key: ValueKey('saving'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Saving…'),
                              ],
                            )
                          : Row(
                              key: const ValueKey('idle'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_rounded, size: 19),
                                const SizedBox(width: 8),
                                Text(editing ? 'Save changes' : 'Save class'),
                              ],
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

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;

  const _Field({required this.label, required this.child, this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        if (helper != null) ...[
          const SizedBox(height: 3),
          Text(helper!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _QuickPicks extends StatelessWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onPick;

  const _QuickPicks({
    required this.values,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          Hoverable(
            builder: (context, hovered) {
              final isSelected = selected == value;
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  onTap: () => onPick(value),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryLight
                          : hovered
                              ? AppColors.background
                              : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: isSelected ? 1.5 : 1.2,
                      ),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String subjectName;
  final String subjectCode;
  final String course;
  final String yearSection;

  const _PreviewCard({
    required this.subjectName,
    required this.subjectCode,
    required this.course,
    required this.yearSection,
  });

  @override
  Widget build(BuildContext context) {
    final seed = subjectCode.isNotEmpty ? subjectCode : subjectName;
    final gradient = AccentPalette.gradientFor(seed);
    final initials = seed.isEmpty
        ? '—'
        : AccentPalette.initialsFor(subjectCode, subjectName);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                'PREVIEW',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border, width: 1.2),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.base,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: seed.isEmpty
                              ? [AppColors.border, AppColors.border]
                              : gradient,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: seed.isEmpty
                              ? AppColors.textMuted
                              : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subjectName.isEmpty ? 'Subject name' : subjectName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: subjectName.isEmpty
                                      ? AppColors.textMuted
                                      : AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subjectCode.isEmpty ? 'SUBJECT CODE' : subjectCode,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: subjectCode.isEmpty
                                  ? AppColors.textMuted
                                  : gradient.first,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: AppColors.border.withValues(alpha: 0.9)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusBadge(
                      label: course.isEmpty ? 'Course' : course,
                      color: AppColors.textSecondary,
                      background: AppColors.background,
                      icon: Icons.school_outlined,
                    ),
                    StatusBadge(
                      label: yearSection.isEmpty ? 'Section' : yearSection,
                      color: AppColors.textSecondary,
                      background: AppColors.background,
                      icon: Icons.layers_outlined,
                    ),
                    const StatusBadge(
                      label: '0 students',
                      color: AppColors.primary,
                      background: AppColors.primaryLight,
                      icon: Icons.groups_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This is how the class will appear on your dashboard.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

class _NextStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  const _NextStep({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightChoice extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _WeightChoice({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.primaryDark : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}