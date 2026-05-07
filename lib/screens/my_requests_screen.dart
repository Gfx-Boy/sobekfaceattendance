import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../models/request.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

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
        padding: const EdgeInsets.all(16),
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

    return Container(
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Text(req.status.name.toUpperCase(),
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
