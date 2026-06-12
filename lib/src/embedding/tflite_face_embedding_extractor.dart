import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../config/face_recognition_config.dart';
import '../core/exceptions.dart';
import 'face_embedding_extractor.dart';

class TfliteFaceEmbeddingExtractor implements FaceEmbeddingExtractor {
  TfliteFaceEmbeddingExtractor({required FaceRecognitionConfig config})
      : _config = config;

  final FaceRecognitionConfig _config;
  Interpreter? _interpreter;

  @override
  Future<void> initialize() async {
    if (_interpreter != null) return;

    try {
      final options = InterpreterOptions();
      final numThreads = _config.numThreads;
      if (numThreads != null) {
        options.threads = numThreads;
      }
      _interpreter = await Interpreter.fromAsset(
        _config.modelAssetPath,
        options: options,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FaceEmbeddingException(
          'Failed to initialize TensorFlow Lite model.',
          error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<List<double>> extract(image.Image face) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw const FaceEmbeddingException(
        'Embedding extractor is not initialized.',
      );
    }

    try {
      final input = _imageToModelInput(face);
      final output = List.filled(_config.embeddingSize, 0.0).reshape([
        1,
        _config.embeddingSize,
      ]);

      interpreter.run(input, output);
      return output.first.cast<double>();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FaceEmbeddingException('Failed to extract face embedding.', error),
        stackTrace,
      );
    }
  }

  List<dynamic> _imageToModelInput(image.Image inputImage) {
    final resized = image.copyResize(
      inputImage,
      width: _config.inputWidth,
      height: _config.inputHeight,
    );

    final values = Float32List(
      _config.inputWidth * _config.inputHeight * 3,
    );

    var index = 0;
    for (var y = 0; y < _config.inputHeight; y++) {
      for (var x = 0; x < _config.inputWidth; x++) {
        final pixel = resized.getPixel(x, y);
        values[index++] = (pixel.r.toDouble() - 127.5) / 127.5;
        values[index++] = (pixel.g.toDouble() - 127.5) / 127.5;
        values[index++] = (pixel.b.toDouble() - 127.5) / 127.5;
      }
    }

    return values.reshape([
      1,
      _config.inputHeight,
      _config.inputWidth,
      3,
    ]);
  }

  @override
  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
  }
}
