import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../models/request.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/change_password_dialog.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with SingleTickerProviderStateMixin {
  List<AppRequest> _myRequests = [];
  bool _loading = true;
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      if (me != null) {
        _myRequests = await ApiService().getRequests(me.id);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<AppRequest> _filterByStatus(String status) {
    return _myRequests.where((r) {
      if (r.status.name != status) return false;
      if (_query.isEmpty) return true;
      final q = _query;
      return r.title.toLowerCase().contains(q) ||
          r.description.toLowerCase().contains(q) ||
          r.typeDisplayName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.myRequests),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryBlue,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: context.colors.textSecondary,
          tabs: [
            Tab(text: '${S.pending} (${_filterByStatus('pending').length})'),
            Tab(text: '${S.approved} (${_filterByStatus('approved').length})'),
            Tab(text: '${S.rejected} (${_filterByStatus('rejected').length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.colors.textPrimary),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: S.search,
                    prefixIcon: Icon(Icons.search,
                        color: context.colors.textMuted),
                    filled: true,
                    fillColor: context.colors.cardBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: context.colors.surfaceBorder),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList('pending'),
                    _buildList('approved'),
                    _buildList('rejected'),
                  ],
                ),
              ),
            ]),
    );
  }

  Widget _buildList(String status) {
    final filtered = _filterByStatus(status);
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 60, color: context.colors.textMuted),
            const SizedBox(height: 12),
            Text(S.noStatusRequests(status),
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: filtered.map(_buildItem).toList(),
      ),
    );
  }

  Widget _buildItem(AppRequest req) {
    final statusColor = switch (req.status) {
      RequestStatus.approved => AppTheme.accentGreen,
      RequestStatus.rejected => AppTheme.checkOutRed,
      _ => AppTheme.warningAmber,
    };

    return GestureDetector(
      onTap: () => _showDetail(req),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(req.title,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      '${req.category.name.toUpperCase()} · ${req.typeDisplayName}',
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                      '${S.createdAt}: ${DateFormat('MMM d, y · HH:mm', S.locale.languageCode).format(req.createdAt)}',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 11)),
                  if (req.startDate != null)
                    Text('${S.from}: ${DateFormat('MMM d', S.locale.languageCode).format(req.startDate!)}',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(req.status.name.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ),
                const SizedBox(height: 6),
                Icon(Icons.chevron_right,
                    size: 18, color: context.colors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(AppRequest req) {
    final statusColor = switch (req.status) {
      RequestStatus.approved => AppTheme.accentGreen,
      RequestStatus.rejected => AppTheme.checkOutRed,
      RequestStatus.forwarded => AppTheme.primaryBlue,
      _ => AppTheme.warningAmber,
    };

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: context.colors.textMuted),
            const SizedBox(width: 8),
            Text('$label: ',
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 13)),
            Expanded(
                child: Text(value,
                    style: TextStyle(
                        color: context.colors.textPrimary, fontSize: 13))),
          ]),
        );

    final extraRows = <Widget>[];
    final extra = req.extraFields;
    final permTime = extra['permission_time'] as String?;
    final permHours = extra['permission_hours']?.toString();
    if (permTime != null && permTime.isNotEmpty) {
      String windowText = permTime;
      final hrs = int.tryParse(permHours ?? '');
      final parts = permTime.split(':');
      if (hrs != null && parts.length == 2) {
        final sh = int.tryParse(parts[0]);
        final sm = int.tryParse(parts[1]);
        if (sh != null && sm != null) {
          final endH = (sh + hrs) % 24;
          windowText =
              '$permTime – ${endH.toString().padLeft(2, '0')}:${sm.toString().padLeft(2, '0')}';
        }
      }
      if (permHours != null && permHours.isNotEmpty) {
        windowText += '  (${S.permissionHoursLabel(permHours)})';
      }
      extraRows.add(row(Icons.schedule, S.permissionWindow, windowText));
    }
    extra.forEach((key, value) {
      if (key == 'permission_time' || key == 'permission_hours') return;
      if (value == null || value.toString().trim().isEmpty) return;
      final label = key
          .split('_')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
          .join(' ');
      extraRows.add(row(Icons.info_outline, label, value.toString()));
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: context.colors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Text(req.title,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(req.status.name.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 16),
            row(Icons.category_outlined, S.requestType,
                '${req.typeDisplayName} (${req.category.name.toUpperCase()})'),
            row(Icons.calendar_today, S.createdAt,
                DateFormat('MMM d, y · HH:mm', S.locale.languageCode)
                    .format(req.createdAt)),
            if (req.startDate != null)
              row(Icons.date_range, S.from,
                  DateFormat('MMM d, y', S.locale.languageCode)
                      .format(req.startDate!)),
            if (req.endDate != null)
              row(Icons.date_range, S.end,
                  DateFormat('MMM d, y', S.locale.languageCode)
                      .format(req.endDate!)),
            ...extraRows,
            const SizedBox(height: 12),
            Text(S.description,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(req.description,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 14)),
            if (req.comment != null && req.comment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              row(Icons.comment_outlined, S.comment, req.comment!),
            ],
            if (req.reviewedBy != null && req.reviewedBy!.isNotEmpty)
              row(Icons.rate_review_outlined, S.reviewedBy, req.reviewedBy!),
            // Point 11 — when was the request accepted/rejected.
            if (req.reviewedAt != null)
              row(
                  Icons.schedule,
                  S.reviewedAtLabel,
                  DateFormat('MMM d, y · HH:mm', S.locale.languageCode)
                      .format(req.reviewedAt!)),
            // #5 — an approved password-change request lets the employee set
            // the new password right from here instead of hunting for the
            // action in their profile.
            if (req.type == RequestType.passwordChange &&
                req.status == RequestStatus.approved &&
                (context.read<AuthProvider>().employee?.passwordResetPending ??
                    false)) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_reset),
                  label: Text(S.changePasswordNow),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await showChangePasswordDialog(context);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}
