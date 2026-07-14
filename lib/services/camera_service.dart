import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _streaming = false;
  CameraDescription? _activeCamera;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  CameraDescription? get activeCamera => _activeCamera;
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
    _activeCamera = frontCamera;

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      // nv21/bgra8888 so the preview stream can feed ML Kit for the liveness
      // (blink) check; takePicture still produces a JPEG.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    _isInitialized = true;
  }

  /// Streams preview frames (for the liveness detector).
  Future<void> startImageStream(void Function(CameraImage) onFrame) async {
    if (_controller == null || !_isInitialized || _streaming) return;
    _streaming = true;
    await _controller!.startImageStream(onFrame);
  }

  Future<void> stopImageStream() async {
    if (_controller == null || !_streaming) return;
    _streaming = false;
    try {
      await _controller!.stopImageStream();
    } catch (_) {/* already stopped */}
  }

  Future<File> captureImage() async {
    if (_controller == null || !_isInitialized) {
      throw CameraServiceException('Camera is not initialized');
    }

    // Some devices cannot take a picture while the preview stream is open.
    await stopImageStream();

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
      await stopImageStream();
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
