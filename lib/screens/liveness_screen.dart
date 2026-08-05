import 'package:flutter/material.dart';
import 'package:face_liveness_detector/face_liveness_detector.dart';
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
      setState(() {
        _error = provider.error ?? S.verificationFailed;
        _preparing = false;
      });
      return;
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_preparing) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      S.preparingLivenessCheck,
                      style: const TextStyle(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _start,
                        child: Text(S.tryAgain),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(S.cancel,
                            style: const TextStyle(color: Colors.white70)),
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
