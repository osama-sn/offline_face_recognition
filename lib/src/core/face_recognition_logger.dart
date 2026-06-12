abstract interface class FaceRecognitionLogger {
  void debug(String message);

  void warning(String message, [Object? error, StackTrace? stackTrace]);

  void error(String message, [Object? error, StackTrace? stackTrace]);
}

class NoopFaceRecognitionLogger implements FaceRecognitionLogger {
  const NoopFaceRecognitionLogger();

  @override
  void debug(String message) {}

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}
