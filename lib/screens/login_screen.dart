import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

/// Maps raw ApiException messages to short, user-friendly strings.
String _friendlyError(String? raw) {
  if (raw == null || raw.isEmpty) {
    return S.loginErrorGeneric;
  }
  final e = raw.toLowerCase();
  if (e.contains('socket') ||
      e.contains('cannot reach') ||
      e.contains('host lookup') ||
      e.contains('connection refused') ||
      e.contains('no internet') ||
      e.contains('timed out') ||
      e.contains('timeout')) {
    return S.loginErrorNoInternet;
  }
  if (e.contains('account is on hold')) return S.loginErrorAccountOnHold;
  if (e.contains('branch') && e.contains('on hold')) return S.loginErrorBranchOnHold;
  if (e.contains('branch') && e.contains('closed')) return S.loginErrorBranchClosed;
  if (e.contains('branch') && e.contains('deleted')) return S.loginErrorBranchDeleted;
  if (e.contains('another device') || e.contains('logged in on another')) return S.loginErrorAnotherDevice;
  if (e.contains('401') ||
      e.contains('403') ||
      e.contains('invalid') ||
      e.contains('credentials') ||
      e.contains('unauthorized') ||
      e.contains('incorrect')) {
    return S.loginErrorInvalidCreds;
  }
  return S.loginErrorGeneric;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLogin());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final auth = context.read<AuthProvider>();
    await auth.checkSavedLogin();
    if (!mounted) return;
    if (auth.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      password: _passwordController.text.trim().isNotEmpty
          ? _passwordController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(authProvider.error)),
          backgroundColor: AppTheme.checkOutRed,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      size: 52,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  S.appName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  S.loginTitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: S.emailAddress,
                    hintText: S.enterWorkEmail,
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return S.pleaseEnterEmail;
                    }
                    if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$')
                        .hasMatch(value.trim())) {
                      return S.pleaseEnterValidEmail;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: S.password,
                    hintText: S.enterPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onFieldSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 24),

                // Login button
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleLogin,
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(S.logIn),
                    );
                  },
                ),
                const SizedBox(height: 40),

                // Info note
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: cs.onSurface.withValues(alpha: 0.4),
                          size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          S.loginErrorContactAdmin,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
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
  }
}


