class FaceRecognitionConfig {
  const FaceRecognitionConfig({
    this.modelAssetPath =
        'packages/offline_face_recognition/assets/mobile_face_net.tflite',
    this.inputWidth = 112,
    this.inputHeight = 112,
    this.embeddingSize = 192,
    this.matchThreshold = 0.75,
    this.numThreads,
    this.allowMultipleFacesOnRegistration = false,
    this.maxFacesToRecognize = 3,
  });

  final String modelAssetPath;
  final int inputWidth;
  final int inputHeight;
  final int embeddingSize;
  final double matchThreshold;
  final int? numThreads;
  final bool allowMultipleFacesOnRegistration;
  final int maxFacesToRecognize;
}
