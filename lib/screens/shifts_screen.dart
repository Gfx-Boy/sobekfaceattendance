import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/workspace_models.dart';
import '../providers/workspace_provider.dart';
import '../widgets/workspace_state.dart';

/// Review point 25: the shifts managed on the web, shown on the phone.
///
/// The durations come from the server already computed - it handles the
/// night-shift rollover, so nothing here recalculates them.
class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await context.read<WorkspaceProvider>().loadShifts();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(S.shifts)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : workspace.shifts.isEmpty
              ? WorkspaceStateView(
                  reason: workspace.linkError,
                  emptyMessage: S.noShifts,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: workspace.shifts.length,
                    itemBuilder: (context, i) =>
                        _ShiftCard(shift: workspace.shifts[i]),
                  ),
                ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final WorkspaceShift shift;

  const _ShiftCard({required this.shift});

  /// The API returns times as stored (24h "HH:mm:ss"); trim to "HH:mm".
  String _time(String raw) {
    if (raw.isEmpty) return '—';
    final parts = raw.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBreak = shift.breakMinutes > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shift.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (shift.isNightShift)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.nightlight_round,
                            size: 12, color: Color(0xFF6366F1)),
                        const SizedBox(width: 4),
                        Text(
                          S.nightShift,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${_time(shift.startTime)} – ${_time(shift.endTime)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  shift.workingLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (hasBreak) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.free_breakfast_outlined,
                      size: 16, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 6),
                  Text(
                    '${S.breakLabel}: ${_time(shift.breakStartTime ?? '')} – '
                    '${_time(shift.breakEndTime ?? '')} (${shift.breakMinutes}m)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (shift.employeeCount > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.people_outline,
                      size: 16, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 6),
                  Text(
                    S.employeesCount(shift.employeeCount),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
