import '../models/face_template.dart';

abstract interface class FaceTemplateStore {
  Future<void> initialize();

  Future<void> save(FaceTemplate template);

  Future<FaceTemplate?> findById(String id);

  Future<List<FaceTemplate>> findAll();

  Future<void> delete(String id);

  Future<void> clear();

  Future<void> close();
}
