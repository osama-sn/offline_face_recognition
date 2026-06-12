import 'dart:math';

import '../config/face_recognition_config.dart';
import '../models/face_template.dart';
import '../models/recognition_result.dart';
import 'face_matcher.dart';

class EuclideanFaceMatcher implements FaceMatcher {
  const EuclideanFaceMatcher();

  @override
  RecognitionResult findBestMatch({
    required List<double> embedding,
    required List<FaceTemplate> templates,
    required FaceRecognitionConfig config,
  }) {
    FaceTemplate? bestTemplate;
    var bestDistance = double.infinity;

    for (final template in templates) {
      final distance = _distance(embedding, template.embedding);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestTemplate = template;
      }
    }

    final isMatch =
        bestTemplate != null && bestDistance <= config.matchThreshold;
    final confidence = bestTemplate == null
        ? 0.0
        : (1 - (bestDistance / config.matchThreshold))
            .clamp(0.0, 1.0)
            .toDouble();

    return RecognitionResult(
      embedding: embedding,
      template: isMatch ? bestTemplate : null,
      nearestTemplate: bestTemplate,
      distance: bestTemplate == null ? null : bestDistance,
      confidence: confidence,
      isMatch: isMatch,
    );
  }

  double _distance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;

    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }
}
