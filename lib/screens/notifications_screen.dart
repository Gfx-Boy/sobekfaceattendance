import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  List<AppNotification> _filtered = [];
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _notifications
          : _notifications.where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _loadNotifications() async {
    final employee = context.read<AuthProvider>().employee;
    if (employee == null) return;
    setState(() => _loading = true);
    try {
      _notifications = await ApiService().getNotifications(employee.id);
      _filter();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markRead(AppNotification notif) async {
    final employee = context.read<AuthProvider>().employee;
    if (employee == null || notif.isRead) return;
    try {
      await ApiService().markNotificationRead(employee.id, notif.id);
      _loadNotifications();
    } catch (_) {}
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.requestApproval:
        return Icons.check_circle_outline;
      case NotificationType.requestRejection:
        return Icons.cancel_outlined;
      case NotificationType.hrNotification:
        return Icons.badge_outlined;
      case NotificationType.systemAlert:
        return Icons.warning_amber_outlined;
      case NotificationType.taskAssignment:
        return Icons.task_alt;
      case NotificationType.attendanceAlert:
        return Icons.access_time;
      case NotificationType.payslipAvailable:
        return Icons.receipt_long;
      case NotificationType.evaluationResult:
        return Icons.star_outline;
      case NotificationType.general:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.requestApproval:
        return AppTheme.accentGreen;
      case NotificationType.requestRejection:
        return AppTheme.checkOutRed;
      case NotificationType.hrNotification:
        return AppTheme.warningAmber;
      case NotificationType.systemAlert:
        return AppTheme.checkOutRed;
      case NotificationType.taskAssignment:
        return const Color(0xFF6C63FF);
      case NotificationType.attendanceAlert:
        return AppTheme.primaryBlue;
      case NotificationType.payslipAvailable:
        return Color(0xFF4ECDC4);
      case NotificationType.evaluationResult:
        return Color(0xFFFF6B6B);
      case NotificationType.general:
        return context.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(unreadCount > 0 ? '${S.notifications} ($unreadCount)' : S.notifications),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadNotifications),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: S.searchNotifications,
                prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
                filled: true,
                fillColor: context.colors.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: context.colors.cardBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
                              ),
                              child: Icon(Icons.notifications_off_outlined, size: 36, color: context.colors.textMuted),
                            ),
                            SizedBox(height: 16),
                            Text(S.noNotifications, style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                            SizedBox(height: 6),
                            Text(S.noNotificationsDesc, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _notificationCard(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(AppNotification notif) {
    final color = _colorForType(notif.type);
    final icon = _iconForType(notif.type);
    final ago = _timeAgo(notif.createdAt);

    return GestureDetector(
      onTap: () => _markRead(notif),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead ? context.colors.cardBg : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notif.isRead ? context.colors.surfaceBorder : color.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 14,
                            fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!notif.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  if (notif.body.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(notif.body, style: TextStyle(color: context.colors.textSecondary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  SizedBox(height: 4),
                  Text(ago, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return S.justNow;
    if (diff.inMinutes < 60) return S.mAgo(diff.inMinutes);
    if (diff.inHours < 24) return S.hAgo(diff.inHours);
    if (diff.inDays < 7) return S.dAgo(diff.inDays);
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
