import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// The individual proofs-of-life the user must perform, in a random order.
enum LivenessChallenge {
  /// Open → closed → open eyes. A printed/displayed photo cannot do this.
  blink,

  /// Turn the head clearly to one side and then the other. A pre-recorded
  /// video is unlikely to match the randomized challenge order.
  turnHead,
}

enum LivenessState {
  /// No (single) face in frame yet.
  noFace,

  /// A challenge is in progress — see [LivenessDetector.currentChallenge].
  challenge,

  /// All challenges passed and the face is back to frontal — safe to capture.
  passed,
}

/// On-device liveness gate for the attendance camera (#19 anti-spoofing).
///
/// Pure face matching accepts a photo of the right person shown on another
/// device, so before capture we demand live responses: a randomized sequence
/// of blink + head-turn challenges, performed by ONE continuously-tracked
/// face. Losing or swapping the face restarts the whole sequence.
class LivenessDetector {
  LivenessDetector()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true, // eye-open probabilities
            enableTracking: true, // stable id so the face can't be swapped
            performanceMode: FaceDetectorMode.fast,
          ),
        ) {
    _newSequence();
  }

  final FaceDetector _detector;
  final Random _rng = Random();

  static const double _openThreshold = 0.65;
  static const double _closedThreshold = 0.25;
  static const double _yawThreshold = 22.0; // degrees
  static const double _frontalYaw = 14.0;

  late List<LivenessChallenge> _sequence;
  int _index = 0;
  int? _trackId;

  // blink progress
  bool _sawOpen = false;
  bool _sawClosed = false;
  // head-turn progress
  bool _sawLeft = false;
  bool _sawRight = false;
  // after the last challenge we wait for the face to be frontal again so the
  // captured photo is usable for Rekognition CompareFaces
  bool _challengesDone = false;

  bool _busy = false;
  LivenessState _state = LivenessState.noFace;

  LivenessState get state => _state;
  bool get passed => _state == LivenessState.passed;
  LivenessChallenge? get currentChallenge =>
      _challengesDone || _index >= _sequence.length
          ? null
          : _sequence[_index];
  int get challengeNumber => min(_index + 1, _sequence.length);
  int get challengeCount => _sequence.length;

  void _newSequence() {
    _sequence = List.of(LivenessChallenge.values)..shuffle(_rng);
    _index = 0;
    _trackId = null;
    _sawOpen = false;
    _sawClosed = false;
    _sawLeft = false;
    _sawRight = false;
    _challengesDone = false;
  }

  void reset() {
    _newSequence();
    _state = LivenessState.noFace;
  }

  Future<void> dispose() => _detector.close();

  /// Processes one preview frame; returns the updated state (unchanged if the
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

      // Exactly one face must be present — a second face usually means a real
      // person holding up a photo/phone of someone else.
      if (faces.length != 1) {
        _newSequence(); // progress made by a removed face doesn't carry over
        _state = LivenessState.noFace;
        return _state;
      }
      final face = faces.first;

      // The same physical face must perform the whole sequence.
      if (face.trackingId != null) {
        if (_trackId != null && face.trackingId != _trackId) _newSequence();
        _trackId = face.trackingId;
      }

      if (_challengesDone) {
        // Wait for a frontal pose so the capture works for face matching.
        final yaw = face.headEulerAngleY ?? 0;
        if (yaw.abs() < _frontalYaw) {
          _state = LivenessState.passed;
        }
        return _state;
      }

      switch (_sequence[_index]) {
        case LivenessChallenge.blink:
          final left = face.leftEyeOpenProbability;
          final right = face.rightEyeOpenProbability;
          if (left != null && right != null) {
            final bothOpen =
                left > _openThreshold && right > _openThreshold;
            final bothClosed =
                left < _closedThreshold && right < _closedThreshold;
            if (bothOpen && !_sawOpen) _sawOpen = true;
            if (_sawOpen && bothClosed) _sawClosed = true;
            if (_sawOpen && _sawClosed && bothOpen) _advance();
          }
          break;
        case LivenessChallenge.turnHead:
          final yaw = face.headEulerAngleY;
          if (yaw != null) {
            if (yaw < -_yawThreshold) _sawLeft = true;
            if (yaw > _yawThreshold) _sawRight = true;
            if (_sawLeft && _sawRight) _advance();
          }
          break;
      }
      _state = _challengesDone || _state == LivenessState.passed
          ? _state
          : LivenessState.challenge;
      return _state;
    } catch (_) {
      return _state;
    } finally {
      _busy = false;
    }
  }

  void _advance() {
    _sawOpen = false;
    _sawClosed = false;
    _sawLeft = false;
    _sawRight = false;
    _index += 1;
    if (_index >= _sequence.length) _challengesDone = true;
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
