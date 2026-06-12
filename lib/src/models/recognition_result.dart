import '../detection/detected_face.dart';
import 'face_template.dart';

class RecognitionResult {
  const RecognitionResult({
    required this.embedding,
    required this.isMatch,
    required this.confidence,
    this.template,
    this.nearestTemplate,
    this.distance,
    this.face,
  });

  final List<double> embedding;
  final bool isMatch;
  final double confidence;
  final FaceTemplate? template;
  final FaceTemplate? nearestTemplate;
  final double? distance;
  final DetectedFace? face;

  String? get id => template?.id;

  RecognitionResult copyWith({
    List<double>? embedding,
    bool? isMatch,
    double? confidence,
    FaceTemplate? template,
    FaceTemplate? nearestTemplate,
    double? distance,
    DetectedFace? face,
  }) {
    return RecognitionResult(
      embedding: embedding ?? this.embedding,
      isMatch: isMatch ?? this.isMatch,
      confidence: confidence ?? this.confidence,
      template: template ?? this.template,
      nearestTemplate: nearestTemplate ?? this.nearestTemplate,
      distance: distance ?? this.distance,
      face: face ?? this.face,
    );
  }
}
