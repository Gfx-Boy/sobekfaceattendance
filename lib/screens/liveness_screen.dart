import 'package:flutter/material.dart';
import 'package:face_liveness_detector/face_liveness_detector.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

/// AWS Face Liveness gate for attendance: runs the oval face-scan (a live
/// person is verified server-side by Rekognition), then submits attendance
/// with the session id. Photos, screens, and prints cannot pass the scan.
class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  String? _sessionId;
  String? _error;
  bool _preparing = true;
  bool _openGpsSettings = false;
  bool _openAppSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _preparing = true;
      _error = null;
      _sessionId = null;
    });
    final provider = context.read<AttendanceProvider>();
    await provider.getLocation();
    if (!mounted) return;
    if (provider.currentPosition == null) {
      // Remember WHY location failed so Try Again can open the right
      // settings screen (GPS off / permission denied) like the old flow
      // did (#2E round 5).
      final locEx = provider.locationException;
      setState(() {
        _error = provider.error ?? S.verificationFailed;
        _openGpsSettings = locEx?.needsServiceEnable ?? false;
        _openAppSettings = locEx?.needsSettings ?? false;
        _preparing = false;
      });
      return;
    }
    _openGpsSettings = false;
    _openAppSettings = false;
    try {
      final sid = await ApiService().createLivenessSession();
      if (!mounted) return;
      setState(() {
        _sessionId = sid;
        _preparing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _preparing = false;
      });
    }
  }

  void _onScanComplete() {
    final auth = context.read<AuthProvider>();
    final provider = context.read<AttendanceProvider>();
    final me = auth.employee;
    if (me == null || _sessionId == null) return;
    provider.submitAttendanceWithLiveness(me.id, _sessionId!);
    Navigator.pushReplacementNamed(context, '/verify');
  }

  @override
  Widget build(BuildContext context) {
    // Follows the app's light/dark theme — the previous hard-black screens
    // clashed with the rest of the app in light mode (#2C round 5). The
    // native AWS scan view itself keeps Amazon's fixed design (its colour
    // flashes ARE the security check).
    return Scaffold(
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_preparing) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      S.preparingLivenessCheck,
                      style: TextStyle(color: context.colors.textPrimary),
                    ),
                  ],
                ),
              );
            }
            if (_error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.checkOutRed, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.textPrimary),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          if (_openGpsSettings) {
                            await Geolocator.openLocationSettings();
                          } else if (_openAppSettings) {
                            await Geolocator.openAppSettings();
                          }
                          _start();
                        },
                        child: Text(S.tryAgain),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(S.cancel,
                            style: TextStyle(
                                color: context.colors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              );
            }
            return FaceLivenessDetector(
              sessionId: _sessionId!,
              region: 'us-east-1',
              onComplete: _onScanComplete,
              onError: (errorCode) {
                if (!mounted) return;
                setState(() {
                  _error = '${S.livenessScanFailed}\n($errorCode)';
                });
              },
            );
          },
        ),
      ),
    );
  }
}
