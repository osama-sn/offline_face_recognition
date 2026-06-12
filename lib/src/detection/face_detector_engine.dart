import 'dart:io';

import 'detected_face.dart';

abstract interface class FaceDetectorEngine {
  Future<List<DetectedFace>> detectFromFile(File image);

  Future<void> close();
}
