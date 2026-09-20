import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const double _wideBreakpoint = 900;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _focusEmail = FocusNode();
  final _focusPassword = FocusNode();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _submitting = false;
  bool _submittedOnce = false;
  bool _capsLock = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusEmail.addListener(() => setState(() {}));
    _focusPassword.addListener(() {
      _checkCapsLock();
      setState(() {});
    });
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _emailController.dispose();
    _passwordController.dispose();
    _focusEmail.dispose();
    _focusPassword.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _checkCapsLock();
    return false;
  }

  void _checkCapsLock() {
    final on = _focusPassword.hasFocus &&
        HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Enter your school e-mail.';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return 'That doesn’t look like an e-mail address.';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> _handleLogin() async {
    if (_submitting) return;
    setState(() {
      _submittedOnce = true;
      _error = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = await AuthService.instance.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );

      if (user.isAdmin) {
        await AuthService.instance.signOut();
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = 'That is an administrator account. '
              'Use the administrator sign-in below.';
        });
        HapticFeedback.mediumImpact();
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } on ApiException catch (e) {

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      HapticFeedback.mediumImpact();
      if (e.isUnauthorized) {
        _passwordController.clear();
        _focusPassword.requestFocus();
      }
    } on NetworkException catch (e) {

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong while logging in. Try again.';
      });
    }
  }

  Future<void> _forgotPassword() async {
    await showConfirmDialog(
      context,
      title: 'Reset your password',
      message: 'Password reset isn’t available in the app yet. Ask your school’s '
          'ClassRecord administrator to reset it for you.',
      confirmLabel: 'Got it',
      cancelLabel: 'Close',
      icon: Icons.lock_reset_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= _wideBreakpoint;
          if (!wide) return SafeArea(child: _formPane(compact: true));
          return Row(
            children: [
              Expanded(flex: 5, child: SafeArea(child: _formPane(compact: false))),
              const Expanded(flex: 6, child: _BrandPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _formPane({required bool compact}) {
    final hPad = compact ? 24.0 : 48.0;

    return LayoutBuilder(builder: (context, c) {
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: compact ? 24 : 36),

        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              minHeight: (c.maxHeight - (compact ? 48 : 72)).clamp(0.0, double.infinity),
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  if (compact) _brandRow(compact: true) else const SizedBox.shrink(),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 36 : 48),
                    child: _form(),
                  ),
                  _footer(),
                ],
              ),
          ),
        ),
      );
    });
  }

  Widget _brandRow({required bool compact}) {
    final plate = Container(
      width: compact ? 72 : 44,
      height: compact ? 72 : 44,
      padding: EdgeInsets.all(compact ? 6 : 4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: compact ? 2 : 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: compact ? 22 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
    );

    if (compact) {

      return Column(
        children: [
          plate,
          const SizedBox(height: 12),
          Text('ClassRecord', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          const Text(
            'St. Benilde Center for Global Competence',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.goldDark),
          ),
        ],
      ).animate().fadeIn(duration: 350.ms);
    }

    return Row(
      children: [
        plate,
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ClassRecord',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.15),
            ),
            const Text(
              'St. Benilde',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.goldDark),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  InputDecoration _fieldDecoration({
    required FocusNode focus,
    required IconData icon,
    required String hint,
    Widget? suffix,
  }) {
    final focused = focus.hasFocus;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: focused ? Colors.white : const Color(0xFFF3F6F4),
      hoverColor: const Color(0xFFEDF2EE),
      contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(icon, size: 20, color: focused ? AppColors.primary : AppColors.textMuted),
      ),
      suffixIcon: suffix,
      border: border(const Color(0xFFE3E9E5), 1.2),
      enabledBorder: border(const Color(0xFFE3E9E5), 1.2),
      disabledBorder: border(const Color(0xFFE3E9E5), 1.2),
      focusedBorder: border(AppColors.primary, 1.8),
      errorBorder: border(AppColors.danger.withValues(alpha: 0.7), 1.3),
      focusedErrorBorder: border(AppColors.danger, 1.8),
      errorStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.3),
    );
  }

  Widget _form() {
    final theme = Theme.of(context);
    return AutofillGroup(
      child: Form(
        key: _formKey,
        autovalidateMode:
            _submittedOnce ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _greeting,
              style: theme.textTheme.headlineMedium?.copyWith(fontSize: 34, letterSpacing: -0.8),
            ),
            const SizedBox(height: 8),
            Text(
              'Log in with your school account to pick up where you left off.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.5),
            ),
            const SizedBox(height: 32),

            AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.curve,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _ErrorBanner(
                        message: _error!,
                        onClose: () => setState(() => _error = null),
                      ),
                    ).animate().fadeIn(duration: 200.ms).shakeX(hz: 4, amount: 3, duration: 320.ms),
            ),

            const _FieldLabel('E-mail'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              focusNode: _focusEmail,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              autocorrect: false,
              validator: _validateEmail,
              onFieldSubmitted: (_) => _focusPassword.requestFocus(),
              decoration: _fieldDecoration(
                focus: _focusEmail,
                icon: Icons.mail_outline_rounded,
                hint: 'you@benilde.edu.ph',
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                const Expanded(child: _FieldLabel('Password')),
                TextButton(
                  onPressed: _submitting ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _passwordController,
              focusNode: _focusPassword,
              enabled: !_submitting,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              validator: _validatePassword,
              onFieldSubmitted: (_) => _handleLogin(),
              decoration: _fieldDecoration(
                focus: _focusPassword,
                icon: Icons.lock_outline_rounded,
                hint: 'Enter your password',
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: AppMotion.fast,
              child: _capsLock
                  ? const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.keyboard_capslock_rounded, size: 16, color: AppColors.warning),
                          SizedBox(width: 6),
                          Text(
                            'Caps Lock is on',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submitting ? null : () => setState(() => _rememberMe = !_rememberMe),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 10, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: _submitting
                                ? null
                                : (v) => setState(() => _rememberMe = v ?? false),
                            activeColor: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Keep me signed in on this device',
                          style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            _SubmitButton(loading: _submitting, onPressed: _handleLogin),

            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'New here?',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pushNamed('/accept-invite'),
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: const Text('I have an invitation code'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pushNamed('/admin-login'),
              icon: const Icon(Icons.shield_outlined, size: 17),
              label: const Text('Administrator sign-in'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 80.ms, duration: 350.ms).slideY(begin: 0.03, end: 0, curve: AppMotion.curve);
  }

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 16,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: AppColors.textMuted),
                SizedBox(width: 6),
                Text(
                  'For St. Benilde faculty only',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
            ),
            Hoverable(
              builder: (context, hovered) => GestureDetector(
                onTap: _forgotPassword,
                child: Text(
                  'Need help logging in?',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: hovered ? AppColors.primary : AppColors.textSecondary,
                    decoration: hovered ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _ErrorBanner({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 19, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13.5, color: AppColors.danger, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _SubmitButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      enabled: !loading,
      label: loading ? 'Logging in' : 'Login',
      excludeSemantics: true,
      child: Hoverable(
        enableCursor: !loading,
        builder: (context, hovered) {
          final lifted = hovered && !loading;
          return AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            transform: Matrix4.translationValues(0, lifted ? -1.5 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: lifted ? 0.38 : 0.22),
                  blurRadius: lifted ? 22 : 14,
                  offset: Offset(0, lifted ? 10 : 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF138048), AppColors.primaryDark],
                  ),
                ),
                child: InkWell(
                  onTap: loading ? null : onPressed,
                  borderRadius: radius,
                  splashColor: Colors.white.withValues(alpha: 0.15),
                  highlightColor: Colors.black.withValues(alpha: 0.06),
                  child: SizedBox(
                    height: 54,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: AppMotion.fast,
                        child: loading
                            ? const Row(
                                key: ValueKey('loading'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Logging in…', style: _label),
                                ],
                              )
                            : Row(
                                key: const ValueKey('idle'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Login', style: _label),
                                  const SizedBox(width: 10),
                                  AnimatedSlide(
                                    duration: AppMotion.fast,
                                    offset: Offset(lifted ? 0.25 : 0, 0),
                                    child: const Icon(Icons.arrow_forward_rounded,
                                        size: 19, color: Colors.white),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const TextStyle _label = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(

      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.18),
          radius: 1.05,
          colors: [Color(0xFF15834A), AppColors.primaryDark, Color(0xFF062A17)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DotGridPainter(color: Colors.white.withValues(alpha: 0.045), spacing: 24),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final logo = (c.maxWidth * 0.40).clamp(170.0, 280.0).toDouble();
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Crest(size: logo),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
                    child: Text(
                      'Class records for St. Benilde faculty',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Crest extends StatelessWidget {
  final double size;

  const _Crest({required this.size});

  @override
  Widget build(BuildContext context) {
    final frame = size * 1.62;

    Widget ring(double d, {required Color color, double width = 1, Color? fill}) => Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: color, width: width),
          ),
        );

    final crest = SizedBox(
      width: frame,
      height: frame,
      child: Stack(
        alignment: Alignment.center,
        children: [

          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                stops: const [0.35, 1.0],
                colors: [
                  AppColors.gold.withValues(alpha: 0.22),
                  AppColors.gold.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),

          ring(size * 1.46, color: Colors.white.withValues(alpha: 0.10))
              .animate()
              .fadeIn(delay: 350.ms, duration: 700.ms)
              .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutCubic, duration: 900.ms),
          ring(
            size * 1.22,
            color: AppColors.gold.withValues(alpha: 0.55),
            width: 1.4,
            fill: Colors.white.withValues(alpha: 0.05),
          )
              .animate()
              .fadeIn(delay: 200.ms, duration: 600.ms)
              .scale(begin: const Offset(0.86, 0.86), curve: Curves.easeOutCubic, duration: 800.ms),

          Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.08),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppColors.gold, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
          )
              .animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutCubic, duration: 700.ms),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        crest,
        const SizedBox(height: 8),
        Text(
          'St. Benilde',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontSize: 34,
                letterSpacing: -0.4,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Center for Global Competence',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 28, height: 1.4, color: AppColors.gold.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            const Text(
              'ClassRecord',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 28, height: 1.4, color: AppColors.gold.withValues(alpha: 0.7)),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}