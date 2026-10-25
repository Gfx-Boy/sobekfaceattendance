import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

/// Prompts the signed-in employee for a new password (with confirmation and
/// visibility toggles) and submits it via [ApiService.selfChangePassword].
/// Refreshes the profile afterwards so `passwordResetPending` clears.
Future<void> showChangePasswordDialog(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final emp = auth.employee;
  if (emp == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final pwd = TextEditingController();
  final pwd2 = TextEditingController();
  bool obscure1 = true;
  bool obscure2 = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: ctx.colors.cardBg,
        title: Text(S.changePasswordNow),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwd,
              obscureText: obscure1,
              style: TextStyle(color: ctx.colors.textPrimary),
              decoration: InputDecoration(
                hintText: S.newPasswordHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  icon: Icon(obscure1
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setD(() => obscure1 = !obscure1),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwd2,
              obscureText: obscure2,
              style: TextStyle(color: ctx.colors.textPrimary),
              decoration: InputDecoration(
                hintText: S.confirmNewPassword,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  icon: Icon(obscure2
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setD(() => obscure2 = !obscure2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.save)),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (pwd.text.length < 6) {
    messenger.showSnackBar(
      SnackBar(
          content: Text(S.passwordTooShort),
          backgroundColor: AppTheme.warningAmber),
    );
    return;
  }
  if (pwd.text != pwd2.text) {
    messenger.showSnackBar(
      SnackBar(
          content: Text(S.passwordsDontMatch),
          backgroundColor: AppTheme.warningAmber),
    );
    return;
  }
  try {
    await ApiService()
        .selfChangePassword(employeeId: emp.id, newPassword: pwd.text);
    // Refresh profile so the pending flag is cleared.
    await auth.refreshProfile();
    messenger.showSnackBar(
      SnackBar(
          content: Text(S.passwordUpdated),
          backgroundColor: AppTheme.accentGreen),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
    );
  }
}
