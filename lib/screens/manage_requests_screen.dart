import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/request.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class ManageRequestsScreen extends StatefulWidget {
  const ManageRequestsScreen({super.key});

  @override
  State<ManageRequestsScreen> createState() => _ManageRequestsScreenState();
}

class _ManageRequestsScreenState extends State<ManageRequestsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AppRequest> _requests = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      setState(() => _loading = true);
      final employee = context.read<AuthProvider>().employee;
      final branchId = (employee?.role == UserRole.branchAdmin || employee?.role == UserRole.hr)
          ? employee?.branchId
          : null;
      _requests = await ApiService().getAllRequests(branchId: branchId);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AppRequest> _filterByStatus(String status) {
    Iterable<AppRequest> base =
        status == 'all' ? _requests : _requests.where((r) => r.status.name == status);
    if (_searchQuery.isNotEmpty) {
      base = base.where((r) {
        return r.title.toLowerCase().contains(_searchQuery) ||
            r.description.toLowerCase().contains(_searchQuery) ||
            (r.employeeName.toLowerCase().contains(_searchQuery)) ||
            r.type.name.toLowerCase().contains(_searchQuery);
      });
    }
    return base.toList();
  }

  Future<void> _reviewRequest(AppRequest request, String status) async {
    final employee = context.read<AuthProvider>().employee;
    try {
      await ApiService().reviewRequest(
        request.id,
        status,
        reviewedBy: employee?.name ?? 'Admin',
      );
      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request $status'), backgroundColor: AppTheme.accentGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.manageRequests),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryBlue,
          tabs: [
            Tab(text: '${S.pending} (${_filterByStatus('pending').length})'),
            Tab(text: S.approved),
            Tab(text: S.rejected),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: S.searchRequests,
                      prefixIcon: Icon(Icons.search,
                          color: context.colors.textSecondary),
                      filled: true,
                      fillColor: context.colors.cardBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadRequests,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_filterByStatus('pending')),
                        _buildList(_filterByStatus('approved')),
                        _buildList(_filterByStatus('rejected')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList(List<AppRequest> requests) {
    if (requests.isEmpty) {
      return Center(child: Text(S.noRequests, style: TextStyle(color: context.colors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      itemBuilder: (context, index) => _requestCard(requests[index]),
    );
  }

  Widget _requestCard(AppRequest request) {
    final employee = context.read<AuthProvider>().employee;
    final isOwnRequest = employee?.id == request.employeeId;
    final isHR = employee?.role == UserRole.hr;
    // HR cannot approve their own requests
    final canReview = !(isHR && isOwnRequest);

    Color statusColor;
    switch (request.status) {
      case RequestStatus.pending: statusColor = AppTheme.warningAmber; break;
      case RequestStatus.approved: statusColor = AppTheme.accentGreen; break;
      case RequestStatus.rejected: statusColor = AppTheme.checkOutRed; break;
      case RequestStatus.forwarded: statusColor = AppTheme.primaryBlue; break;
    }

    return GestureDetector(
      onTap: () => _showRequestDetails(request),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(request.title, style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(request.status.name.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            SizedBox(height: 6),
            Row(children: [
              Icon(Icons.person_outline, size: 13, color: context.colors.textSecondary),
              SizedBox(width: 4),
              Text(request.employeeName, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              if (request.employeeEmail != null && request.employeeEmail!.isNotEmpty) ...[
                SizedBox(width: 8),
                Icon(Icons.email_outlined, size: 13, color: context.colors.textMuted),
                SizedBox(width: 2),
                Expanded(child: Text(request.employeeEmail!, style: TextStyle(color: context.colors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis)),
              ],
            ]),
            if (request.branchName != null && request.branchName!.isNotEmpty) ...[
              SizedBox(height: 2),
              Row(children: [
                Icon(Icons.business, size: 12, color: context.colors.textMuted),
                SizedBox(width: 4),
                Text(request.branchName!, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
              ]),
            ],
            SizedBox(height: 4),
            Text('${request.typeDisplayName} · ${DateFormat('MMM d, y', S.locale.languageCode).format(request.createdAt)}',
                style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
            if (request.status == RequestStatus.pending && canReview) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reviewRequest(request, 'rejected'),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.checkOutRed)),
                      child: Text(S.reject, style: const TextStyle(color: AppTheme.checkOutRed)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _reviewRequest(request, 'approved'),
                      child: Text(S.approve),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _localizedStatus(RequestStatus status) {
    switch (status) {
      case RequestStatus.approved: return S.approved.toUpperCase();
      case RequestStatus.rejected: return S.rejected.toUpperCase();
      case RequestStatus.forwarded: return S.pending.toUpperCase();
      default: return S.pending.toUpperCase();
    }
  }

  void _showRequestDetails(AppRequest request) {
    Color statusColor;
    switch (request.status) {
      case RequestStatus.pending: statusColor = AppTheme.warningAmber; break;
      case RequestStatus.approved: statusColor = AppTheme.accentGreen; break;
      case RequestStatus.rejected: statusColor = AppTheme.checkOutRed; break;
      case RequestStatus.forwarded: statusColor = AppTheme.primaryBlue; break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.colors.surfaceBorder, borderRadius: BorderRadius.circular(2)))),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(request.title, style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_localizedStatus(request.status), style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 16),
            _detailRow(Icons.person_outline, S.employee, request.employeeName),
            if (request.employeeEmail != null && request.employeeEmail!.isNotEmpty)
              _detailRow(Icons.email_outlined, S.email, request.employeeEmail!),
            if (request.branchName != null && request.branchName!.isNotEmpty)
              _detailRow(Icons.business, S.branch, request.branchName!),
            _detailRow(Icons.category_outlined, S.requestType, '${request.typeDisplayName} (${request.category.name.toUpperCase()})'),
            _detailRow(Icons.calendar_today, S.createdAt, DateFormat('MMM d, y · HH:mm', S.locale.languageCode).format(request.createdAt)),
            if (request.startDate != null)
              _detailRow(Icons.date_range, S.from, DateFormat('MMM d, y', S.locale.languageCode).format(request.startDate!)),
            if (request.endDate != null)
              _detailRow(Icons.date_range, S.end, DateFormat('MMM d, y', S.locale.languageCode).format(request.endDate!)),
            SizedBox(height: 12),
            Text(S.description, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text(request.description, style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
            if (request.reviewedBy != null) ...[
              const SizedBox(height: 12),
              _detailRow(Icons.rate_review_outlined, S.reviewedBy, request.reviewedBy!),
            ],
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.comment_outlined, S.comment, request.comment!),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: context.colors.textMuted),
        SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
        Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
      ]),
    );
  }
}
