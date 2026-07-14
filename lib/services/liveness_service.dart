import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Result of feeding one camera frame to [LivenessDetector].
enum LivenessState {
  /// No (single) face in frame yet.
  noFace,

  /// Face found, waiting for the user to blink.
  waitingForBlink,

  /// Eyes are closed — mid-blink.
  blinking,

  /// A full blink (open → closed → open) was observed: a static photo or a
  /// screen showing a picture cannot do this.
  passed,
}

/// On-device liveness gate for the attendance camera (#19 anti-spoofing).
///
/// A photo of the right person shown on another device fools pure face
/// matching, so before capture we require proof of life: a blink, tracked via
/// ML Kit's eye-open classification across the live preview stream.
class LivenessDetector {
  LivenessDetector()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true, // eye-open probabilities
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  final FaceDetector _detector;

  static const double _openThreshold = 0.65;
  static const double _closedThreshold = 0.25;

  bool _sawOpen = false;
  bool _sawClosed = false;
  bool _busy = false;

  LivenessState _state = LivenessState.noFace;
  LivenessState get state => _state;
  bool get passed => _state == LivenessState.passed;

  void reset() {
    _sawOpen = false;
    _sawClosed = false;
    _state = LivenessState.noFace;
  }

  Future<void> dispose() => _detector.close();

  /// Processes one preview frame. Returns the updated state (unchanged if the
  /// frame was skipped because the previous one is still being processed).
  Future<LivenessState> processFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    if (_state == LivenessState.passed) return _state;
    if (_busy) return _state;
    _busy = true;
    try {
      final input = _toInputImage(image, camera, deviceOrientation);
      if (input == null) return _state;
      final faces = await _detector.processImage(input);

      // Exactly one face must be present — two faces usually means a real
      // person holding up a photo/phone of someone else.
      if (faces.length != 1) {
        _state = LivenessState.noFace;
        return _state;
      }
      final face = faces.first;
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;
      if (left == null || right == null) {
        _state = LivenessState.waitingForBlink;
        return _state;
      }

      final bothOpen = left > _openThreshold && right > _openThreshold;
      final bothClosed = left < _closedThreshold && right < _closedThreshold;

      if (bothOpen && !_sawOpen) _sawOpen = true;
      if (_sawOpen && bothClosed) _sawClosed = true;
      if (_sawOpen && _sawClosed && bothOpen) {
        _state = LivenessState.passed;
      } else if (bothClosed) {
        _state = LivenessState.blinking;
      } else {
        _state = LivenessState.waitingForBlink;
      }
      return _state;
    } catch (_) {
      return _state;
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else {
      final compensation = orientations[deviceOrientation];
      if (compensation == null) return null;
      final raw = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + compensation) % 360
          : (camera.sensorOrientation - compensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(raw);
    }
    if (rotation == null) return null;

    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
