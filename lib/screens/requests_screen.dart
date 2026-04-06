import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../models/employee.dart';
import '../models/request.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> with SingleTickerProviderStateMixin {
  List<AppRequest> _myRequests = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMyRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      if (me != null) {
        _myRequests = await ApiService().getRequests(me.id);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<AppRequest> _filterByStatus(String status) =>
      _myRequests.where((r) => r.status.name == status).toList();

  void _openCreateRequest(String category, String type) {
    Navigator.pushNamed(context, '/create-request', arguments: {
      'category': category,
      'type': type,
    }).then((result) {
      if (result == true) _loadMyRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.employee?.role ?? UserRole.employee;
    final isManager = role == UserRole.superAdmin || role == UserRole.branchAdmin || role == UserRole.hr;
    final canCreateRequests = role != UserRole.superAdmin && role != UserRole.branchAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.manageRequests),
        actions: [
          if (isManager)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: S.manageRequests,
              onPressed: () => Navigator.pushNamed(context, '/manage-requests'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (canCreateRequests) ...[
            // Request creation section - scrollable top part
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (ctx, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.itRequests, style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          _buildRequestGrid([
                            _RequestItem(icon: Icons.alternate_email, label: S.emailUserAccount, color: AppTheme.primaryBlue, category: 'IT', type: 'emailAndUserAccount'),
                            _RequestItem(icon: Icons.security, label: S.accessRight, color: AppTheme.accentGreen, category: 'IT', type: 'accessRight'),
                            _RequestItem(icon: Icons.devices, label: S.equipment, color: AppTheme.warningAmber, category: 'IT', type: 'equipment'),
                            _RequestItem(icon: Icons.apps, label: S.applications, color: AppTheme.checkOutPink, category: 'IT', type: 'applications'),
                          ]),
                          SizedBox(height: 20),
                          Text(S.hrRequests, style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          _buildRequestGrid([
                            _RequestItem(icon: Icons.flight_takeoff, label: S.businessMission, color: AppTheme.primaryBlue, category: 'HR', type: 'businessMission'),
                            _RequestItem(icon: Icons.how_to_reg, label: S.permission, color: AppTheme.accentGreen, category: 'HR', type: 'permission'),
                            _RequestItem(icon: Icons.beach_access, label: S.vacation, color: AppTheme.warningAmber, category: 'HR', type: 'vacation'),
                            _RequestItem(icon: Icons.exit_to_app, label: S.leave, color: AppTheme.checkOutPink, category: 'HR', type: 'leave'),
                          ]),
                          SizedBox(height: 20),
                          Text('${S.myRequests}', style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          TabBar(
                            controller: _tabController,
                            indicatorColor: AppTheme.primaryBlue,
                            labelColor: AppTheme.primaryBlue,
                            unselectedLabelColor: context.colors.textSecondary,
                            isScrollable: true,
                            tabs: [
                              Tab(text: '${S.pending} (${_filterByStatus('pending').length})'),
                              Tab(text: '${S.approved} (${_filterByStatus('approved').length})'),
                              Tab(text: '${S.rejected} (${_filterByStatus('rejected').length})'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStatusList('pending'),
                    _buildStatusList('approved'),
                    _buildStatusList('rejected'),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Manager view - just tabs
            TabBar(
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
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStatusList('pending'),
                  _buildStatusList('approved'),
                  _buildStatusList('rejected'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusList(String status) {
    if (_loading) return Center(child: CircularProgressIndicator());
    final filtered = _filterByStatus(status);
    if (filtered.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 60, color: context.colors.textMuted),
          SizedBox(height: 12),
          Text(S.noStatusRequests(status), style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
        ],
      ));
    }
    return RefreshIndicator(
      onRefresh: _loadMyRequests,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: filtered.map(_buildRequestListItem).toList(),
      ),
    );
  }

  Widget _buildRequestListItem(AppRequest req) {
    final statusColor = switch (req.status) {
      RequestStatus.approved => AppTheme.accentGreen,
      RequestStatus.rejected => AppTheme.checkOutRed,
      _ => AppTheme.warningAmber,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req.title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                SizedBox(height: 2),
                Text('${req.category.name.toUpperCase()} · ${req.typeDisplayName}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                SizedBox(height: 2),
                Text('${S.createdAt}: ${DateFormat('MMM d, y · HH:mm').format(req.createdAt)}', style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                if (req.startDate != null)
                  Text('From: ${DateFormat('MMM d').format(req.startDate!)}', style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(req.status.name.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestGrid(List<_RequestItem> items) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: items.map((item) => _buildRequestCard(item)).toList(),
    );
  }

  Widget _buildRequestCard(_RequestItem item) {
    return GestureDetector(
      onTap: () => _openCreateRequest(item.category, item.type),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: item.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            SizedBox(height: 8),
            Text(item.label, style: TextStyle(color: context.colors.textSecondary, fontSize: 10, height: 1.3), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RequestItem {
  final IconData icon;
  final String label;
  final Color color;
  final String category;
  final String type;

  const _RequestItem({required this.icon, required this.label, required this.color, required this.category, required this.type});
}
