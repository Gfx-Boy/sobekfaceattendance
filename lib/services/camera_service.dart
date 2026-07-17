import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get hasFrontCamera =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front);

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraServiceException('No cameras available on this device');
    }

    // Prefer front camera for face capture
    final frontCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    _isInitialized = true;
  }

  Future<File> captureImage() async {
    if (_controller == null || !_isInitialized) {
      throw CameraServiceException('Camera is not initialized');
    }

    final XFile xFile = await _controller!.takePicture();

    // Save to app's temporary directory
    final Directory tempDir = await getTemporaryDirectory();
    final String fileName =
        'face_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final String filePath = path.join(tempDir.path, fileName);

    final File savedFile = await File(xFile.path).copy(filePath);
    return savedFile;
  }

  Future<void> dispose() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      _isInitialized = false;
    }
  }
}

class CameraServiceException implements Exception {
  final String message;
  CameraServiceException(this.message);

  @override
  String toString() => 'CameraServiceException: $message';
}
