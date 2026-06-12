import 'dart:io';
import 'dart:ui';

import 'package:image/image.dart' as image;

import 'config/face_recognition_config.dart';
import 'core/exceptions.dart';
import 'core/face_recognition_logger.dart';
import 'detection/detected_face.dart';
import 'detection/face_detector_engine.dart';
import 'detection/mlkit_face_detector_engine.dart';
import 'embedding/face_embedding_extractor.dart';
import 'embedding/tflite_face_embedding_extractor.dart';
import 'matching/euclidean_face_matcher.dart';
import 'matching/face_matcher.dart';
import 'models/face_template.dart';
import 'models/recognition_result.dart';
import 'models/registration_result.dart';
import 'storage/face_template_store.dart';
import 'storage/sqflite_face_template_store.dart';

class OfflineFaceRecognition {
  OfflineFaceRecognition._({
    required FaceRecognitionConfig config,
    required FaceDetectorEngine detector,
    required FaceEmbeddingExtractor extractor,
    required FaceMatcher matcher,
    required FaceTemplateStore store,
    required FaceRecognitionLogger logger,
  })  : _config = config,
        _detector = detector,
        _extractor = extractor,
        _matcher = matcher,
        _store = store,
        _logger = logger;

  final FaceRecognitionConfig _config;
  final FaceDetectorEngine _detector;
  final FaceEmbeddingExtractor _extractor;
  final FaceMatcher _matcher;
  final FaceTemplateStore _store;
  final FaceRecognitionLogger _logger;

  static Future<OfflineFaceRecognition> create({
    FaceRecognitionConfig config = const FaceRecognitionConfig(),
    FaceDetectorEngine? detector,
    FaceEmbeddingExtractor? extractor,
    FaceMatcher? matcher,
    FaceTemplateStore? store,
    FaceRecognitionLogger logger = const NoopFaceRecognitionLogger(),
  }) async {
    final instance = OfflineFaceRecognition._(
      config: config,
      detector: detector ?? MlKitFaceDetectorEngine(),
      extractor: extractor ?? TfliteFaceEmbeddingExtractor(config: config),
      matcher: matcher ?? const EuclideanFaceMatcher(),
      store: store ?? SqfliteFaceTemplateStore(),
      logger: logger,
    );
    await instance.initialize();
    return instance;
  }

  Future<void> initialize() async {
    _logger.debug('Initializing offline face recognition.');
    await _store.initialize();
    await _extractor.initialize();
  }

  Future<RegistrationResult> register({
    required File image,
    required String id,
    String? label,
    Map<String, Object?> metadata = const {},
  }) async {
    final faces = await _detector.detectFromFile(image);
    if (faces.isEmpty) {
      throw const FaceRegistrationException(
        'No face was detected in the registration image.',
      );
    }
    if (faces.length > 1 && !_config.allowMultipleFacesOnRegistration) {
      throw const FaceRegistrationException(
        'Multiple faces were detected in the registration image.',
      );
    }

    final decoded = await _decodeImage(image);
    final face = faces.first;
    final croppedFace = _crop(decoded, face.boundingBox);
    final embedding = await _extractor.extract(croppedFace);
    final now = DateTime.now();

    final template = FaceTemplate(
      id: id,
      label: label,
      embedding: embedding,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );

    await _store.save(template);
    return RegistrationResult(template: template, face: face);
  }

  Future<RecognitionResult> recognizeImage(File imageFile) async {
    final faces = await _detector.detectFromFile(imageFile);
    if (faces.isEmpty) {
      throw const FaceRecognitionMatchException(
        'No face was detected in the image.',
      );
    }

    final decoded = await _decodeImage(imageFile);
    final face = faces.first;
    final croppedFace = _crop(decoded, face.boundingBox);
    final embedding = await _extractor.extract(croppedFace);
    final templates = await _store.findAll();
    final result = _matcher.findBestMatch(
      embedding: embedding,
      templates: templates,
      config: _config,
    );

    return result.copyWith(face: face);
  }

  Future<RecognitionResult> recognize({required File image}) {
    return recognizeImage(image);
  }

  Future<RecognitionResult> recognizeFaceImage(
    image.Image faceImage, {
    DetectedFace? face,
  }) async {
    final embedding = await _extractor.extract(faceImage);
    final templates = await _store.findAll();
    final result = _matcher.findBestMatch(
      embedding: embedding,
      templates: templates,
      config: _config,
    );

    return result.copyWith(face: face);
  }

  Future<List<FaceTemplate>> listTemplates() => _store.findAll();

  Future<FaceTemplate?> findTemplate(String id) => _store.findById(id);

  Future<void> deleteTemplate(String id) => _store.delete(id);

  Future<void> clear() => _store.clear();

  Future<void> dispose() async {
    await _detector.close();
    await _extractor.close();
    await _store.close();
  }

  Future<image.Image> _decodeImage(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = image.decodeImage(bytes);
    if (decoded == null) {
      throw const FaceRecognitionMatchException(
          'Image format is not supported.');
    }
    return decoded;
  }

  image.Image _crop(image.Image source, Rect box) {
    final left = box.left.clamp(0, source.width - 1).toInt();
    final top = box.top.clamp(0, source.height - 1).toInt();
    final right = box.right.clamp(left + 1, source.width).toInt();
    final bottom = box.bottom.clamp(top + 1, source.height).toInt();

    return image.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }
}
