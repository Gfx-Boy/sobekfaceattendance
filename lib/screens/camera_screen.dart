import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../l10n/app_localizations.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceProvider>().initializeCamera();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Consumer<AttendanceProvider>(
          builder: (context, provider, _) {
            if (provider.currentStep == AttendanceStep.captured) {
              // Show preview of captured image
              return _CapturedPreview(provider: provider);
            }

            if (provider.currentStep == AttendanceStep.failed) {
              return _ErrorView(provider: provider);
            }

            if (provider.currentStep == AttendanceStep.initializingCamera) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      S.initializingCamera,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            }

            final cameraController = provider.cameraService.controller;
            if (cameraController == null ||
                !provider.cameraService.isInitialized) {
              return Center(
                child: Text(
                  S.cameraNotAvailable,
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

            return Stack(
              children: [
                // Camera preview
                Positioned.fill(
                  child: cameraController.buildPreview(),
                ),
                // Face guide overlay
                Center(
                  child: Container(
                    width: 260,
                    height: 340,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(130),
                    ),
                  ),
                ),
                // Instructions
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          S.positionFaceInFrame,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Top bar
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 28),
                    onPressed: () {
                      provider.reset();
                      Navigator.pop(context);
                    },
                  ),
                ),
                // Capture button
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: provider.currentStep == AttendanceStep.cameraReady
                          ? () => provider.captureImage()
                          : null,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black87,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CapturedPreview extends StatelessWidget {
  final AttendanceProvider provider;

  const _CapturedPreview({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () {
                  provider.reset();
                  Navigator.pop(context);
                },
              ),
              Text(
                S.preview,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        // Image preview
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                provider.capturedImage!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: Text(
                    S.retake,
                    style: TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: () => provider.initializeCamera(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(S.proceed),
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/verify');
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final AttendanceProvider provider;

  const _ErrorView({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              provider.error ?? S.somethingWentWrong,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.initializeCamera(),
              child: Text(S.tryAgain),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                provider.reset();
                Navigator.pop(context);
              },
              child:
                  Text(S.goBack, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
