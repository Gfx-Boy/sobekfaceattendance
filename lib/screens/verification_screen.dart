import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/location_service.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVerification();
    });
  }

  Future<void> _startVerification() async {
    final provider = context.read<AttendanceProvider>();
    final auth = context.read<AuthProvider>();

    // Step 1: Get location
    await provider.getLocation();
    if (provider.currentStep == AttendanceStep.failed) return;

    // Step 2: Submit attendance (upload + verify)
    if (auth.employee != null) {
      await provider.submitAttendance(auth.employee!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, _) {
        final showButtons =
            provider.currentStep == AttendanceStep.success ||
                provider.currentStep == AttendanceStep.failed;
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(child: _buildStatusIcon(provider.currentStep)),
                  const SizedBox(height: 24),
                  Text(
                    provider.stepMessage,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildStepIndicators(provider),
                  const SizedBox(height: 24),
                  if (provider.currentStep == AttendanceStep.success)
                    _buildSuccessDetails(provider),
                  if (provider.currentStep == AttendanceStep.failed)
                    _buildErrorDetails(provider),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          bottomNavigationBar: showButtons
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: _buildBottomButtons(context, provider),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildStatusIcon(AttendanceStep step) {
    switch (step) {
      case AttendanceStep.success:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.accentGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: AppTheme.accentGreen,
            size: 80,
          ),
        );
      case AttendanceStep.failed:
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.checkOutRed.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.cancel,
            color: AppTheme.checkOutRed,
            size: 80,
          ),
        );
      default:
        return const SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: AppTheme.primaryBlue,
          ),
        );
    }
  }

  Widget _buildStepIndicators(AttendanceProvider provider) {
    final steps = [
      _StepInfo(S.faceCaptured, AttendanceStep.captured, Icons.face),
      _StepInfo(
          S.locationAcquired, AttendanceStep.locationReady, Icons.location_on),
      _StepInfo(S.imageUploaded, AttendanceStep.uploading, Icons.cloud_upload),
      _StepInfo(
          S.identityVerified, AttendanceStep.verifying, Icons.verified_user),
    ];

    final currentIndex = _getStepIndex(provider.currentStep);

    return Column(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isCompleted = currentIndex > index;
        final isActive = currentIndex == index;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppTheme.accentGreen
                      : isActive
                          ? AppTheme.primaryBlue
                          : AppTheme.cardBgLighter,
                ),
                child: Icon(
                  isCompleted ? Icons.check : step.icon,
                  color: isCompleted || isActive
                      ? Colors.white
                      : context.colors.textMuted,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 15,
                  color: isCompleted
                      ? AppTheme.accentGreen
                      : isActive
                          ? context.colors.textPrimary
                          : context.colors.textSecondary,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (isActive && provider.currentStep != AttendanceStep.success)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  int _getStepIndex(AttendanceStep step) {
    switch (step) {
      case AttendanceStep.idle:
      case AttendanceStep.initializingCamera:
      case AttendanceStep.cameraReady:
      case AttendanceStep.capturing:
      case AttendanceStep.captured:
        return 0;
      case AttendanceStep.gettingLocation:
        return 1;
      case AttendanceStep.locationReady:
      case AttendanceStep.uploading:
        return 2;
      case AttendanceStep.verifying:
        return 3;
      case AttendanceStep.success:
        return 5; // all done
      case AttendanceStep.failed:
        return -1;
    }
  }

  Widget _buildSuccessDetails(AttendanceProvider provider) {
    final result = provider.verificationResult;
    final typeLabel = switch (provider.attendanceType) {
      'sign_out' => 'Sign Out',
      'break_start' => 'Break Start',
      'break_end' => 'Break End',
      _ => 'Sign In',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _detailRow('Type', typeLabel),
            const Divider(),
            _detailRow('Face Match',
                '${result?.faceMatchConfidence?.toStringAsFixed(1) ?? '-'}%'),
            const Divider(),
            _detailRow(
                'Liveness', result?.livenessDetected == true ? 'Verified' : 'N/A'),
            const Divider(),
            _detailRow('Location',
                '${provider.currentPosition?.latitude.toStringAsFixed(4)}, ${provider.currentPosition?.longitude.toStringAsFixed(4)}'),
            const Divider(),
            _detailRow('Time', _formatTime(DateTime.now())),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDetails(AttendanceProvider provider) {
    final locEx = provider.locationException;
    return Card(
      color: AppTheme.checkOutRed.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.warning_amber, color: AppTheme.checkOutRed, size: 32),
            const SizedBox(height: 8),
            Text(
              _friendlyError(provider.error),
              style: const TextStyle(color: AppTheme.checkOutRed),
              textAlign: TextAlign.center,
            ),
            if (locEx != null) ..._buildLocationActionButtons(locEx),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLocationActionButtons(LocationServiceException locEx) {
    if (locEx.needsServiceEnable) {
      return [
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.location_on),
          label: const Text('Open Location Settings'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
          onPressed: () => Geolocator.openLocationSettings(),
        ),
      ];
    }
    if (locEx.needsSettings) {
      return [
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.settings),
          label: const Text('Open App Settings'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
          onPressed: () => Geolocator.openAppSettings(),
        ),
      ];
    }
    return [];
  }

  Widget _buildBottomButtons(
      BuildContext context, AttendanceProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (provider.currentStep == AttendanceStep.failed)
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(S.tryAgain),
            onPressed: () {
              provider.reset();
              Navigator.pushReplacementNamed(context, '/camera');
            },
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            provider.reset();
            Navigator.pushNamedAndRemoveUntil(
                context, '/main', (route) => false);
          },
          child: Text(S.backToHome),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _friendlyError(String? raw) {
    if (raw == null || raw.isEmpty) return S.verificationFailed;
    final lower = raw.toLowerCase();
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return S.errorTimeout;
    }
    if (lower.contains('socket') || lower.contains('cannot reach') || lower.contains('network')) {
      return S.errorNoInternet;
    }
    if (lower.contains('500') || lower.contains('internal server')) {
      return S.errorServer;
    }
    if (lower.contains('face') && lower.contains('not') && lower.contains('match')) {
      return S.errorFaceNotRecognized;
    }
    if (lower.contains('no face') || lower.contains('face not detected')) {
      return S.errorNoFace;
    }
    if (lower.contains('location')) {
      return raw;
    }
    if (lower.contains('outside') || lower.contains('geofence') || lower.contains('radius')) {
      return S.errorGeofence;
    }
    return S.verificationFailed;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _StepInfo {
  final String label;
  final AttendanceStep step;
  final IconData icon;

  _StepInfo(this.label, this.step, this.icon);
}
