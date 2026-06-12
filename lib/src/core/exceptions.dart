sealed class FaceRecognitionException implements Exception {
  const FaceRecognitionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return '$runtimeType: $message';
    return '$runtimeType: $message ($cause)';
  }
}

class FaceRecognitionInitializationException extends FaceRecognitionException {
  const FaceRecognitionInitializationException(super.message, [super.cause]);
}

class FaceDetectionException extends FaceRecognitionException {
  const FaceDetectionException(super.message, [super.cause]);
}

class FaceRegistrationException extends FaceRecognitionException {
  const FaceRegistrationException(super.message, [super.cause]);
}

class FaceEmbeddingException extends FaceRecognitionException {
  const FaceEmbeddingException(super.message, [super.cause]);
}

class FaceStorageException extends FaceRecognitionException {
  const FaceStorageException(super.message, [super.cause]);
}

class FaceRecognitionMatchException extends FaceRecognitionException {
  const FaceRecognitionMatchException(super.message, [super.cause]);
}
