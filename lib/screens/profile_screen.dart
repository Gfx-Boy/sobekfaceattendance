import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;
  String? _localImageUrl; // cache-busted URL after upload

  Future<void> _pickAndUploadImage({ImageSource? source}) async {
    final auth = context.read<AuthProvider>();
    final employee = auth.employee;
    if (employee == null) return;

    // If no source specified, show bottom sheet to choose
    if (source == null) {
      final chosen = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(S.camera),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(S.gallery),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      source = chosen;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      // Evict old cached image before re-uploading
      final oldUrl = _localImageUrl ?? employee.profileImageUrl;
      if (oldUrl != null) {
        await NetworkImage(oldUrl).evict();
        imageCache.clear();
        imageCache.clearLiveImages();
      }
      final api = ApiService();
      final newUrl = await api.uploadProfileImage(employee.id, File(picked.path));
      // Update auth provider immediately so all widgets using employee.profileImageUrl refresh
      auth.updateProfileImageUrl(newUrl);
      // Add cache-buster so NetworkImage fetches fresh image even if URL is same
      setState(() => _localImageUrl = '$newUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.profileImageUpdated), backgroundColor: AppTheme.accentGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.failedToUploadImage}: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final employee = auth.employee;
    final role = employee?.role ?? UserRole.employee;

    return PopScope(
      canPop: !_uploading,
      child: Scaffold(
      appBar: AppBar(
        title: Text(S.profile),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.checkOutRed),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(S.confirmLogout),
                  content: Text(S.confirmLogoutMsg),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(S.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.checkOutRed),
                      child: Text(S.logout),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await auth.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Avatar with upload button
            GestureDetector(
              onTap: _uploading
                  ? null
                  : () {
                      // Fullscreen view if image exists, else pick new
                      final imgUrl = _localImageUrl ?? employee?.profileImageUrl;
                      if (imgUrl != null) {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: EdgeInsets.zero,
                            child: Stack(
                              children: [
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Center(
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        imgUrl,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 40, right: 16,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        _pickAndUploadImage();
                      }
                    },
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                    backgroundImage: (_localImageUrl ?? employee?.profileImageUrl) != null
                        ? NetworkImage(_localImageUrl ?? employee!.profileImageUrl!)
                        : null,
                    child: (_localImageUrl ?? employee?.profileImageUrl) == null
                        ? Text(
                            employee?.name.isNotEmpty == true
                                ? employee!.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _uploading ? null : _pickAndUploadImage,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.scaffoldBg, width: 2),
                        ),
                        child: _uploading
                            ? const Padding(
                                padding: EdgeInsets.all(6),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
            Text(
              employee?.name ?? 'Employee',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              employee?.roleDisplayName ?? 'Employee',
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            // Info cards
            _infoTile(Icons.email_outlined, S.email, employee?.email ?? '-'),
            _infoTile(Icons.business_outlined, S.department,
                employee?.department ?? '-'),
            _infoTile(Icons.location_city_outlined, S.branch,
                employee?.branchName ?? '-'),
            _infoTile(
                Icons.badge_outlined, S.position, employee?.position ?? '-'),
            _infoTile(
                Icons.phone_outlined, S.phone, employee?.phone ?? '-'),
            _infoTile(Icons.location_on_outlined, S.address,
                employee?.address ?? '-'),
            const SizedBox(height: 24),
            // Language toggle
            _buildLanguageToggle(),
            const SizedBox(height: 8),
            // Theme toggle
            _buildThemeToggle(),
            const SizedBox(height: 24),
            // Quick actions
            _actionTile(
              Icons.history,
              role == UserRole.superAdmin || role == UserRole.branchAdmin
                  ? S.attendanceReports
                  : S.attendanceHistory,
              () {
                final role = context.read<AuthProvider>().employee?.role;
                if (role == UserRole.superAdmin || role == UserRole.branchAdmin) {
                  Navigator.pushNamed(context, '/reports');
                } else {
                  Navigator.pushNamed(context, '/history');
                }
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildLanguageToggle() {
    final localeProvider = context.watch<LocaleProvider>();
    final isAr = localeProvider.locale.languageCode == 'ar';
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.language, color: colors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(S.language, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () => localeProvider.setLocale(const Locale('en')),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: !isAr ? AppTheme.primaryBlue.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: !isAr ? AppTheme.primaryBlue : colors.surfaceBorder),
              ),
              child: Text('EN', style: TextStyle(color: !isAr ? AppTheme.primaryBlue : colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => localeProvider.setLocale(const Locale('ar')),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isAr ? AppTheme.primaryBlue.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isAr ? AppTheme.primaryBlue : colors.surfaceBorder),
              ),
              child: Text('AR', style: TextStyle(color: isAr ? AppTheme.primaryBlue : colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle() {
    final themeProvider = context.watch<ThemeProvider>();
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode, color: colors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(themeProvider.isDark ? S.darkMode : S.lightMode, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          Switch(
            value: themeProvider.isDark,
            activeColor: AppTheme.primaryBlue,
            onChanged: (_) => themeProvider.toggle(),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.textMuted, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.surfaceBorder, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
