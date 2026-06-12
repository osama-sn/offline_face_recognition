# offline_face_recognition

Offline face detection, face registration, embedding extraction, and live recognition for Flutter.

This package runs fully on-device with no backend required.

## Features

- Face detection with Google ML Kit
- Face registration from image files or camera capture
- TensorFlow Lite embedding extraction
- Local storage for face templates
- Offline recognition with Euclidean matching
- Live camera stream recognition
- Extensible architecture with replaceable storage and matcher layers

## Platform Support

Currently tested for:

- Android
- iOS

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  offline_face_recognition: ^0.1.0
```

## Assets

The package includes a default TensorFlow Lite model:

```text
assets/mobile_face_net.tflite
```

You usually do not need to pass a custom model path unless you want to swap the model.

## Permissions

Your host app must request camera and gallery permissions.

### Android

Add these permissions to your app manifest:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

If you use the live camera UI, keeping the activity in portrait mode is recommended.

### iOS

Add these usage descriptions to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for offline face recognition.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app lets you pick face images from your photo library.</string>
```

## Quick Start

```dart
import 'dart:io';

import 'package:offline_face_recognition/offline_face_recognition.dart';

final faceRecognition = await OfflineFaceRecognition.create();

await faceRecognition.register(
  image: File('/path/to/image.jpg'),
  id: 'user_1',
  label: 'User One',
);

final result = await faceRecognition.recognize(
  image: File('/path/to/image.jpg'),
);

if (result.isMatch) {
  print('Matched: ${result.template?.label ?? result.template?.id}');
  print('Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
} else {
  print('No match. Distance: ${result.distance}');
}
```

## Live Recognition

For live camera processing, the common flow is:

1. Start a camera stream.
2. Detect faces on each frame.
3. Crop the face region.
4. Extract embeddings with the TFLite model.
5. Compare the embedding against local templates.
6. Update the UI with the latest recognition result.

The example app in this repository demonstrates that flow with a real-time camera preview.

## API

### Create

```dart
final faceRecognition = await OfflineFaceRecognition.create();
```

### Register

```dart
await faceRecognition.register(
  image: file,
  id: 'user_1',
  label: 'User One',
  metadata: {
    'source': 'gallery',
  },
);
```

### Recognize

```dart
final result = await faceRecognition.recognize(image: file);
```

### List templates

```dart
final templates = await faceRecognition.listTemplates();
```

### Delete one

```dart
await faceRecognition.deleteTemplate('user_1');
```

### Clear all

```dart
await faceRecognition.clear();
```

### Dispose

```dart
await faceRecognition.dispose();
```

## Result Model

- `isMatch`: whether the best match passed the configured threshold
- `template`: matched template when recognition succeeds
- `nearestTemplate`: closest known face even when below threshold
- `distance`: Euclidean distance to the nearest template
- `confidence`: normalized score from the matcher
- `face`: detected face metadata for the current frame or image

## Configuration

```dart
final faceRecognition = await OfflineFaceRecognition.create(
  config: const FaceRecognitionConfig(
    matchThreshold: 0.75,
    inputWidth: 112,
    inputHeight: 112,
    embeddingSize: 192,
    numThreads: 2,
  ),
);
```

## Default Model

The package ships with a default MobileFaceNet TFLite model.

If you want to use a custom model, replace the asset path in `FaceRecognitionConfig`.

## Example App

The `example` app includes:

- Live face recognition from the camera stream
- Register face from camera or gallery
- Persistent local storage of saved faces
- Real-time recognition status UI

Run it with:

```powershell
cd example
flutter pub get
flutter run
```

## Limitations

- Best suited for mobile devices
- Requires a face to be clearly visible in the frame
- Recognition quality depends on the model and input image quality
- Live recognition is camera-stream based and should run on the UI thread only if the frame rate is acceptable for your device

## Architecture

See [PACKAGE_DESIGN.md](PACKAGE_DESIGN.md) for the full internal architecture, clean architecture boundaries, and extensibility notes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
