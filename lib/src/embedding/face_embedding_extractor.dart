import 'package:image/image.dart' as image;

abstract interface class FaceEmbeddingExtractor {
  Future<void> initialize();

  Future<List<double>> extract(image.Image face);

  Future<void> close();
}
