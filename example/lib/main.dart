import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:offline_face_recognition/offline_face_recognition.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final faceRecognition = await OfflineFaceRecognition.create();
  final cameras = await availableCameras();

  runApp(
    ExampleApp(
      faceRecognition: faceRecognition,
      cameras: cameras,
    ),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
    required this.faceRecognition,
    required this.cameras,
  });

  final OfflineFaceRecognition faceRecognition;
  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => LiveFaceRecognitionPage(
          faceRecognition: faceRecognition,
          cameras: cameras,
          timeoutDuration: const Duration(seconds: 15), // 15 seconds timeout
          onSuccess: (result) {
            final label = result.template?.label ?? result.template?.id ?? 'Person';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully recognized $label!'),
                backgroundColor: Colors.green,
              ),
            );
            // Put your action here (e.g. navigation, API calls, state updates)
          },
        ),
      ),
    );
  }
}

class LiveFaceRecognitionPage extends StatefulWidget {
  const LiveFaceRecognitionPage({
    super.key,
    required this.faceRecognition,
    required this.cameras,
    this.onSuccess,
    this.timeoutDuration = const Duration(seconds: 30),
  });

  final OfflineFaceRecognition faceRecognition;
  final List<CameraDescription> cameras;
  final void Function(RecognitionResult result)? onSuccess;
  final Duration timeoutDuration;

  @override
  State<LiveFaceRecognitionPage> createState() =>
      _LiveFaceRecognitionPageState();
}

class _LiveFaceRecognitionPageState extends State<LiveFaceRecognitionPage>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: true,
    ),
  );

  CameraController? _controller;
  CameraDescription? _camera;
  Timer? _timeoutTimer;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  var _isInitializing = true;
  var _isProcessingFrame = false;
  var _isRegistering = false;
  var _status = 'Loading camera...';
  var _confidenceText = '';
  RecognitionResult? _lastResult;
  List<FaceTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.15, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _initialize();
  }

  Future<void> _initialize() async {
    await _loadTemplates();
    await _initializeCamera();
    _timeoutTimer = Timer(widget.timeoutDuration, () {
      if (_templates.isNotEmpty && !(_lastResult?.isMatch ?? false) && mounted) {
        _stopImageStream();
        setState(() {
          _status = 'No matching face detected (Timeout).';
          _confidenceText = '';
        });
      }
    });
  }

  Future<void> _loadTemplates() async {
    final templates = await widget.faceRecognition.listTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      if (templates.isEmpty) {
        _status = 'Register a face first.';
      }
    });
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        _isInitializing = false;
        _status = 'No camera found.';
      });
      return;
    }

    _camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      _controller = controller;
      await controller.initialize();
      await _startImageStream();

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _status =
            _templates.isEmpty ? 'Register a face first.' : 'Verifying...';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _status = 'Camera permission or initialization failed.';
      });
    }
  }

  Future<void> _startImageStream() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream((frame) {
      if (!_isProcessingFrame &&
          !_isRegistering &&
          _templates.isNotEmpty) {
        _isProcessingFrame = true;
        _processFrame(frame);
      }
    });
  }

  Future<void> _stopImageStream() async {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _processFrame(CameraImage frame) async {
    try {
      final inputImage = _inputImageFromFrame(frame);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        _updateRecognitionStatus('Verifying...', '');
        return;
      }

      final cameraImage = _cameraImageToImage(frame);
      if (cameraImage == null) return;

      final rotated = img.copyRotate(
        cameraImage,
        angle: _camera?.lensDirection == CameraLensDirection.front ? 270 : 90,
      );
      final face = faces.first;
      final croppedFace = _cropFace(rotated, face.boundingBox);
      final result = await widget.faceRecognition.recognizeFaceImage(
        croppedFace,
        face: DetectedFace(boundingBox: face.boundingBox),
      );

      if (!mounted) return;
      _lastResult = result;

      if (result.isMatch) {
        final label = result.template?.label ?? result.template?.id ?? 'Person';
        _updateRecognitionStatus(
          'Verification success: $label',
          '${(result.confidence * 100).toStringAsFixed(1)}%',
        );
        if (widget.onSuccess != null) {
          await _stopImageStream();
          widget.onSuccess!(result);
        }
      } else {
        _updateRecognitionStatus(
          'Verifying...',
          _distanceToDisplay(result.distance),
        );
      }
    } on FaceRecognitionException catch (error) {
      _updateRecognitionStatus(error.message, '');
    } catch (_) {
      _updateRecognitionStatus('Keep your face inside the frame.', '');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromFrame(CameraImage frame) {
    final camera = _camera;
    if (camera == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(frame.format.raw);

    if (rotation == null || format == null || frame.planes.isEmpty) {
      return null;
    }

    final plane = frame.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  img.Image? _cameraImageToImage(CameraImage frame) {
    if (Platform.isIOS) {
      final plane = frame.planes.first;
      return img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: plane.bytes.buffer,
        rowStride: plane.bytesPerRow,
        bytesOffset: 28,
        order: img.ChannelOrder.bgra,
      );
    }

    return _convertNv21(frame);
  }

  img.Image _convertNv21(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final yuv = frame.planes.first.bytes;
    final output = img.Image(width: width, height: height);
    final frameSize = width * height;

    for (var y = 0, yp = 0; y < height; y++) {
      var uvp = frameSize + (y >> 1) * width;
      var u = 0;
      var v = 0;

      for (var x = 0; x < width; x++, yp++) {
        var yValue = (0xff & yuv[yp]) - 16;
        yValue = yValue < 0 ? 0 : yValue;

        if ((x & 1) == 0) {
          v = (0xff & yuv[uvp++]) - 128;
          u = (0xff & yuv[uvp++]) - 128;
        }

        final r = (1192 * yValue + 1634 * v).clamp(0, 262143);
        final g = (1192 * yValue - 833 * v - 400 * u).clamp(0, 262143);
        final b = (1192 * yValue + 2066 * u).clamp(0, 262143);

        output.setPixelRgb(
          x,
          y,
          (r >> 10) & 0xff,
          (g >> 10) & 0xff,
          (b >> 10) & 0xff,
        );
      }
    }

    return output;
  }

  img.Image _cropFace(img.Image source, Rect box) {
    final left = box.left.clamp(0, source.width - 1).toInt();
    final top = box.top.clamp(0, source.height - 1).toInt();
    final right = box.right.clamp(left + 1, source.width).toInt();
    final bottom = box.bottom.clamp(top + 1, source.height).toInt();

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  Future<void> _registerFromCamera() async {
    final name = await _askForName();
    if (name == null || name.trim().isEmpty) return;

    await _runRegistration(() async {
      await _stopImageStream();
      final picture = await _controller!.takePicture();
      final savedImage = await _saveImageCopy(File(picture.path));
      await _registerFile(savedImage, name.trim());
      await _startImageStream();
    });
  }

  Future<void> _registerFromGallery() async {
    final name = await _askForName();
    if (name == null || name.trim().isEmpty) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return;

    await _runRegistration(() async {
      final savedImage = await _saveImageCopy(File(picked.path));
      await _registerFile(savedImage, name.trim());
    });
  }

  Future<void> _registerFile(File file, String label) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final result = await widget.faceRecognition.register(
      image: file,
      id: id,
      label: label,
      metadata: {'imagePath': file.path},
    );

    await _loadTemplates();
    _lastResult = null;
    _updateRecognitionStatus(
      'Registered ${result.template.label ?? result.template.id}',
      '',
    );
  }

  Future<void> _runRegistration(Future<void> Function() task) async {
    setState(() => _isRegistering = true);
    try {
      await task();
    } on FaceRecognitionException catch (error) {
      _updateRecognitionStatus(error.message, '');
    } catch (error) {
      _updateRecognitionStatus('Registration failed: $error', '');
    } finally {
      if (mounted) {
        setState(() => _isRegistering = false);
      }
      await _startImageStream();
    }
  }

  Future<void> _clearTemplates() async {
    await widget.faceRecognition.clear();
    await _loadTemplates();
    _lastResult = null;
    _updateRecognitionStatus('Register a face first.', '');
  }

  Future<File> _saveImageCopy(File source) async {
    final directory = await getApplicationDocumentsDirectory();
    final facesDirectory = Directory('${directory.path}/registered_faces');
    if (!facesDirectory.existsSync()) {
      facesDirectory.createSync(recursive: true);
    }

    final filename = 'face_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return source.copy('${facesDirectory.path}/$filename');
  }

  Future<String?> _askForName() async {
    _nameController.clear();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Register face'),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name or ID',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_nameController.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String _distanceToDisplay(double? distance) {
    if (distance == null) return '';
    final score = (100 - (distance * 100)).clamp(0, 100).toStringAsFixed(1);
    return '$score%';
  }

  void _updateRecognitionStatus(String status, String confidenceText) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _confidenceText = confidenceText;
    });
  }

  void _showRegisteredFaces() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff151515),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Registered faces',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: _templates.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _clearTemplates();
                          },
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Clear',
                  ),
                ],
              ),
              if (_templates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No faces saved yet.'),
                )
              else
                ..._templates.map((template) => _TemplateTile(template)),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    _nameController.dispose();
    _faceDetector.close();
    _controller?.dispose();
    widget.faceRecognition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isCameraReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: isCameraReady
                ? CameraPreview(controller)
                : const ColoredBox(color: Colors.black),
          ),
          const Positioned.fill(child: _CameraGradient()),
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Image.asset(
                'assets/face_shape.png',
                width: MediaQuery.of(context).size.width,
                fit: BoxFit.fitWidth,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _TopBar(
                registeredCount: _templates.length,
                onShowRegisteredFaces: _showRegisteredFaces,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 128,
            child: _LiveStatus(
              isLoading: _isInitializing || _isRegistering,
              isSuccess: _lastResult?.isMatch ?? false,
              status: _status,
              confidenceText: _confidenceText,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: _BottomActions(
              isBusy: _isInitializing || _isRegistering,
              onRegisterCamera: _registerFromCamera,
              onRegisterGallery: _registerFromGallery,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraGradient extends StatelessWidget {
  const _CameraGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.72),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.registeredCount,
    required this.onShowRegisteredFaces,
  });

  final int registeredCount;
  final VoidCallback onShowRegisteredFaces;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Live face recognition',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onShowRegisteredFaces,
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Registered faces',
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                '$registeredCount saved',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({
    required this.isLoading,
    required this.isSuccess,
    required this.status,
    required this.confidenceText,
  });

  final bool isLoading;
  final bool isSuccess;
  final String status;
  final String confidenceText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSuccess ? Colors.greenAccent : Colors.white24,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSuccess)
              const Icon(Icons.check_circle, color: Colors.greenAccent)
            else if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.center_focus_strong, color: Colors.white),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (confidenceText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '($confidenceText)',
                style: TextStyle(
                  color: isSuccess ? Colors.greenAccent : Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isBusy,
    required this.onRegisterCamera,
    required this.onRegisterGallery,
  });

  final bool isBusy;
  final VoidCallback onRegisterCamera;
  final VoidCallback onRegisterGallery;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: isBusy ? null : onRegisterCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Register camera'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isBusy ? null : onRegisterGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
          ),
        ),
      ],
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile(this.template);

  final FaceTemplate template;

  @override
  Widget build(BuildContext context) {
    final imagePath = template.metadata['imagePath'] as String?;
    final imageFile = imagePath == null ? null : File(imagePath);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: imageFile != null && imageFile.existsSync()
              ? Image.file(imageFile, fit: BoxFit.cover)
              : const ColoredBox(
                  color: Colors.white12,
                  child: Icon(Icons.person_outline),
                ),
        ),
      ),
      title: Text(template.label ?? template.id),
      subtitle: Text(
        '${template.embedding.length} values',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
