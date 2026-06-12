import '../detection/detected_face.dart';
import 'face_template.dart';

class RegistrationResult {
  const RegistrationResult({
    required this.template,
    required this.face,
  });

  final FaceTemplate template;
  final DetectedFace face;
}
