import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/workspace_models.dart';
import '../providers/workspace_provider.dart';
import '../widgets/workspace_state.dart';

/// Review point 20: the web app's CRM, in two parts - Leads and Deals.
///
/// Both are read from the same pipelines the web uses, grouped by stage so the
/// board reads the same way on a phone as it does in a browser.
class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final workspace = context.read<WorkspaceProvider>();
    // Both boards at once; one failing should not hide the other.
    await Future.wait([workspace.loadLeads(), workspace.loadDeals()]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(S.crm),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: S.leads),
            Tab(text: S.deals),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _Board<WorkspaceLead>(
                  stages: workspace.leads,
                  reason: workspace.linkError,
                  emptyMessage: S.noLeads,
                  onRetry: _load,
                  itemBuilder: (lead) => _LeadCard(lead: lead),
                ),
                _Board<WorkspaceDeal>(
                  stages: workspace.deals,
                  reason: workspace.linkError,
                  emptyMessage: S.noDeals,
                  onRetry: _load,
                  itemBuilder: (deal) => _DealCard(deal: deal),
                ),
              ],
            ),
    );
  }
}

/// A stage-grouped list. Stages with nothing in them are still shown, because
/// an empty column is information on a pipeline.
class _Board<T> extends StatelessWidget {
  final List<WorkspaceStage<T>> stages;
  final String? reason;
  final String emptyMessage;
  final VoidCallback onRetry;
  final Widget Function(T item) itemBuilder;

  const _Board({
    required this.stages,
    required this.reason,
    required this.emptyMessage,
    required this.onRetry,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final total = stages.fold<int>(0, (sum, s) => sum + s.items.length);

    if (stages.isEmpty || total == 0) {
      return WorkspaceStateView(
        reason: reason,
        emptyMessage: emptyMessage,
        onRetry: onRetry,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          for (final stage in stages) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Row(
                children: [
                  Text(
                    stage.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${stage.items.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (stage.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '—',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final item in stage.items) itemBuilder(item),
          ],
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final WorkspaceLead lead;

  const _LeadCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          lead.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lead.subject.isNotEmpty) Text(lead.subject),
            if (lead.email.isNotEmpty)
              Text(lead.email, style: Theme.of(context).textTheme.bodySmall),
            if (lead.phone.isNotEmpty)
              Text(lead.phone, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        isThreeLine: lead.email.isNotEmpty && lead.phone.isNotEmpty,
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  final WorkspaceDeal deal;

  const _DealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(symbol: '', decimalDigits: 2);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          deal.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: deal.phone.isEmpty
            ? null
            : Text(deal.phone, style: theme.textTheme.bodySmall),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (deal.price > 0)
              Text(
                money.format(deal.price),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (!deal.isActive)
              Text(
                deal.status.isEmpty ? '—' : deal.status,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
