import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key});

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await AuthService.instance.acceptInvite(
        email: _email.text,
        code: _code.text,
        password: _password.text,
        rememberMe: false,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t set up the account. Try again.',
        };
      });
    }
  }

  ({String label, double value, Color color}) _strength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;

    if (value.isEmpty) return (label: '', value: 0, color: AppColors.border);
    if (score <= 2) return (label: 'Weak', value: 0.33, color: AppColors.danger);
    if (score == 3) return (label: 'Fair', value: 0.66, color: AppColors.warning);
    return (label: 'Strong', value: 1, color: AppColors.success);
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength(_password.text);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to login',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Set up your account'),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(Icons.mark_email_read_outlined,
                          size: 26, color: AppColors.primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Use your invitation code',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your department gave you a code. Enter it here with the e-mail '
                      'address it was issued for, then choose your own password — nobody '
                      'else will ever know it.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 18, color: AppColors.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _email,
                      enabled: !_saving,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your school e-mail',
                        prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Enter your e-mail address';
                        final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                        return ok ? null : 'That e-mail doesn’t look right';
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _code,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,

                      inputFormatters: [_UpperCaseFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Invitation code',
                        hintText: 'BCR-XXXX-XXXX',
                        prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().length < 6) ? 'Enter the code you were given' : null,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _password,
                      enabled: !_saving,
                      obscureText: !_show,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Choose a password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _show ? 'Hide password' : 'Show password',
                          icon: Icon(_show
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) return 'Use at least 8 characters';
                        if (v.length > 72) return 'Use 72 characters or fewer';
                        return null;
                      },
                    ),

                    if (_password.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: strength.value,
                                minHeight: 5,
                                backgroundColor: AppColors.border,
                                valueColor: AlwaysStoppedAnimation(strength.color),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            strength.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: strength.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _confirm,
                      enabled: !_saving,
                      obscureText: !_show,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                      ),
                      validator: (v) => v != _password.text ? 'The passwords don’t match' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 50)),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('Create my account'),
                    ),
                    const SizedBox(height: 14),

                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
                      child: const Text('I already have an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}