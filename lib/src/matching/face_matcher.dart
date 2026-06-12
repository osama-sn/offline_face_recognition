import '../config/face_recognition_config.dart';
import '../models/face_template.dart';
import '../models/recognition_result.dart';

abstract interface class FaceMatcher {
  RecognitionResult findBestMatch({
    required List<double> embedding,
    required List<FaceTemplate> templates,
    required FaceRecognitionConfig config,
  });
}
