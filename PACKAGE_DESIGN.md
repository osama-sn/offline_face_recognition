# Package Design

## Goals

`offline_face_recognition` should feel like a production-grade package, not copied app code. The package owns the domain pipeline and exposes a small API:

```dart
await faceRecognition.register(image: imageFile, id: 'user_1');
final result = await faceRecognition.recognizeImage(imageFile);
```

The app owns permissions, UI, routing, and business decisions.

## Architecture

```text
lib/
  offline_face_recognition.dart
  src/
    config/
    core/
    detection/
    embedding/
    matching/
    registration/
    recognition/
    storage/
    camera/
    logging/
```

## Clean Architecture

Domain models:

- `DetectedFace`
- `FaceTemplate`
- `RecognitionResult`
- `RegistrationResult`

Ports:

- `FaceDetectorEngine`
- `FaceEmbeddingExtractor`
- `FaceMatcher`
- `FaceTemplateStore`
- `FaceRecognitionLogger`

Adapters:

- `MlKitFaceDetectorEngine`
- `TfliteFaceEmbeddingExtractor`
- `SqfliteFaceTemplateStore`
- `EuclideanFaceMatcher`
- `CameraFrameProcessor`

Application service:

- `OfflineFaceRecognition`

## SOLID

- Single Responsibility: detection, embedding, matching, and storage are separate services.
- Open/Closed: users can swap ML Kit, TensorFlow Lite, storage, or matcher without changing the public facade.
- Liskov Substitution: all implementations depend on stable interfaces.
- Interface Segregation: storage does not know about camera frames; matcher does not know about SQL.
- Dependency Inversion: `OfflineFaceRecognition` depends on abstractions, not concrete ML/database classes.

## Core Modules

### Face Detection

Responsible for finding face bounding boxes in an image. Default adapter uses Google ML Kit face detection.

### Face Registration

Detects one face, crops it, extracts an embedding, and stores a `FaceTemplate`.

### Embedding Extraction

Normalizes a cropped face image to the model input size and runs TensorFlow Lite inference.

### Face Matching

Compares embeddings using Euclidean distance by default. Future matchers can support cosine similarity or indexed nearest-neighbor search.

### Camera Stream Processing

Converts camera frames into images/input images, throttles processing, detects faces, extracts embeddings, and emits recognition events.

### Local Storage

Stores face templates locally with sqflite by default. The interface allows Hive, Isar, encrypted storage, or app-owned repositories.

### TensorFlow Lite Inference

Owns interpreter lifecycle, thread count, input normalization, and output shape.

### Error Handling

Typed exceptions: initialization, detection, registration, inference, storage, and recognition errors.

### Logging

Logger interface avoids hard-coded `print` statements and lets apps integrate Crashlytics, Sentry, or package-level debug logs.

## Public API

```dart
final recognition = await OfflineFaceRecognition.create();

await recognition.register(
  image: file,
  id: 'user_1',
  label: 'User 1',
);

final result = await recognition.recognizeImage(file);
final templates = await recognition.listTemplates();
await recognition.deleteTemplate('user_1');
await recognition.clear();
await recognition.dispose();
```

## Internal API

Internal adapters live under `src/` and are exported only when they are useful extension points. App code should prefer the facade.

## Extensibility

Planned extension points:

- Custom model path and input/output dimensions
- Custom normalization strategy
- Custom matcher and threshold
- Custom encrypted store
- Liveness detection plugin
- Multiple templates per identity
- Background isolate inference
- Web-safe adapter stubs
