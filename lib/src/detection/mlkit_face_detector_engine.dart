import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/exceptions.dart';
import 'detected_face.dart';
import 'face_detector_engine.dart';

class MlKitFaceDetectorEngine implements FaceDetectorEngine {
  MlKitFaceDetectorEngine({FaceDetectorOptions? options})
      : _detector = FaceDetector(
          options: options ??
              FaceDetectorOptions(
                performanceMode: FaceDetectorMode.accurate,
                enableTracking: true,
              ),
        );

  final FaceDetector _detector;

  @override
  Future<List<DetectedFace>> detectFromFile(File image) async {
    try {
      final inputImage = InputImage.fromFile(image);
      final faces = await _detector.processImage(inputImage);
      return faces
          .map(
            (face) => DetectedFace(
              boundingBox: face.boundingBox,
              trackingId: face.trackingId,
              headEulerAngleX: face.headEulerAngleX,
              headEulerAngleY: face.headEulerAngleY,
              headEulerAngleZ: face.headEulerAngleZ,
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FaceDetectionException(
            'Failed to detect faces from image file.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> close() => _detector.close();
}
