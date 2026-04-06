import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/employee.dart';
import '../models/system_settings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  SystemSettings? _settings;

  // Form fields
  String _timezone = 'Asia/Riyadh';
  int _utcOffset = 3;
  TimeOfDay _workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEnd = const TimeOfDay(hour: 18, minute: 0);
  int _breakMinutes = 60;

  static const _timezones = [
    {'name': 'UTC-12 (Baker Island)', 'tz': 'Etc/GMT+12', 'offset': -12},
    {'name': 'UTC-11 (Samoa)', 'tz': 'Pacific/Samoa', 'offset': -11},
    {'name': 'UTC-10 (Hawaii)', 'tz': 'Pacific/Honolulu', 'offset': -10},
    {'name': 'UTC-9 (Alaska)', 'tz': 'America/Anchorage', 'offset': -9},
    {'name': 'UTC-8 (Pacific US)', 'tz': 'America/Los_Angeles', 'offset': -8},
    {'name': 'UTC-7 (Mountain US)', 'tz': 'America/Denver', 'offset': -7},
    {'name': 'UTC-6 (Central US)', 'tz': 'America/Chicago', 'offset': -6},
    {'name': 'UTC-5 (Eastern US)', 'tz': 'America/New_York', 'offset': -5},
    {'name': 'UTC-4 (Atlantic)', 'tz': 'America/Halifax', 'offset': -4},
    {'name': 'UTC-3 (Buenos Aires)', 'tz': 'America/Argentina/Buenos_Aires', 'offset': -3},
    {'name': 'UTC-2 (South Georgia)', 'tz': 'Atlantic/South_Georgia', 'offset': -2},
    {'name': 'UTC-1 (Azores)', 'tz': 'Atlantic/Azores', 'offset': -1},
    {'name': 'UTC+0 (London / GMT)', 'tz': 'Europe/London', 'offset': 0},
    {'name': 'UTC+1 (Paris / Berlin)', 'tz': 'Europe/Paris', 'offset': 1},
    {'name': 'UTC+2 (Cairo / Athens)', 'tz': 'Africa/Cairo', 'offset': 2},
    {'name': 'UTC+3 (Riyadh / Moscow)', 'tz': 'Asia/Riyadh', 'offset': 3},
    {'name': 'UTC+3:30 (Tehran)', 'tz': 'Asia/Tehran', 'offset': 3},
    {'name': 'UTC+4 (Dubai / Muscat)', 'tz': 'Asia/Dubai', 'offset': 4},
    {'name': 'UTC+5 (Karachi)', 'tz': 'Asia/Karachi', 'offset': 5},
    {'name': 'UTC+5:30 (Mumbai)', 'tz': 'Asia/Kolkata', 'offset': 5},
    {'name': 'UTC+6 (Dhaka)', 'tz': 'Asia/Dhaka', 'offset': 6},
    {'name': 'UTC+7 (Bangkok)', 'tz': 'Asia/Bangkok', 'offset': 7},
    {'name': 'UTC+8 (Singapore)', 'tz': 'Asia/Singapore', 'offset': 8},
    {'name': 'UTC+9 (Tokyo)', 'tz': 'Asia/Tokyo', 'offset': 9},
    {'name': 'UTC+10 (Sydney)', 'tz': 'Australia/Sydney', 'offset': 10},
    {'name': 'UTC+11 (Vladivostok)', 'tz': 'Asia/Vladivostok', 'offset': 11},
    {'name': 'UTC+12 (Auckland)', 'tz': 'Pacific/Auckland', 'offset': 12},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await ApiService().getSettings();
      setState(() {
        _settings = settings;
        _timezone = settings.timezone;
        _utcOffset = settings.utcOffset;
        _breakMinutes = settings.breakDurationMinutes;
        // Parse working hours
        final startParts = settings.workingHours.start.split(':');
        _workStart = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        final endParts = settings.workingHours.end.split(':');
        _workEnd = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updates = {
        'timezone': _timezone,
        'utc_offset': _utcOffset,
        'working_hours': {
          'start': '${_workStart.hour.toString().padLeft(2, '0')}:${_workStart.minute.toString().padLeft(2, '0')}',
          'end': '${_workEnd.hour.toString().padLeft(2, '0')}:${_workEnd.minute.toString().padLeft(2, '0')}',
        },
        'break_duration_minutes': _breakMinutes,
      };
      await ApiService().updateSettings(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.settingsSaved), backgroundColor: AppTheme.accentGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _workStart : _workEnd,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _workStart = picked;
        } else {
          _workEnd = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.systemSettings),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(S.save, style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timezone Section
                  _sectionTitle(S.timezone),
                  SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.selectTimezone, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                        SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _timezones.any((t) => t['tz'] == _timezone) ? _timezone : 'Asia/Riyadh',
                          dropdownColor: context.colors.cardBgLighter,
                          style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: context.colors.cardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          isExpanded: true,
                          items: _timezones
                              .map((t) => DropdownMenuItem(
                                    value: t['tz'] as String,
                                    child: Text(t['name'] as String, style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            final tz = _timezones.firstWhere((t) => t['tz'] == v);
                            setState(() {
                              _timezone = v;
                              _utcOffset = tz['offset'] as int;
                            });
                          },
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Current offset: UTC${_utcOffset >= 0 ? '+' : ''}$_utcOffset',
                          style: TextStyle(color: context.colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // Working Hours (non-SA only)
                  if (context.read<AuthProvider>().employee?.role != UserRole.superAdmin) ...[
                    const SizedBox(height: 20),
                    _sectionTitle(S.workingHours),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: Row(
                        children: [
                          Expanded(child: _timeButton(S.start, _workStart, () => _pickTime(true))),
                          const SizedBox(width: 12),
                          Expanded(child: _timeButton(S.end, _workEnd, () => _pickTime(false))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle(S.breakDuration),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: Row(
                        children: [
                          _breakOption(30),
                          const SizedBox(width: 8),
                          _breakOption(45),
                          const SizedBox(width: 8),
                          _breakOption(60),
                          const SizedBox(width: 8),
                          _breakOption(90),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Language Section
                  _sectionTitle(S.language),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: _cardDecoration(),
                    child: Row(
                      children: [
                        _langOption('en', S.english),
                        const SizedBox(width: 8),
                        _langOption('ar', S.arabic),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Version 1.0',
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
    );
  }

  Widget _timeButton(String label, TimeOfDay time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
            SizedBox(height: 4),
            Text(
              time.format(context),
              style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakOption(int minutes) {
    final selected = _breakMinutes == minutes;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _breakMinutes = minutes),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryBlue.withValues(alpha: 0.15) : context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primaryBlue : context.colors.surfaceBorder,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: Text(
              '${minutes}m',
              style: TextStyle(
                color: selected ? AppTheme.primaryBlue : context.colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _langOption(String code, String label) {
    final localeProvider = context.watch<LocaleProvider>();
    final selected = localeProvider.locale.languageCode == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => localeProvider.setLocale(Locale(code)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryBlue.withValues(alpha: 0.15) : context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primaryBlue : context.colors.surfaceBorder,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.primaryBlue : context.colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
