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
            final customMessage = result.template?.metadata['customMessage'] as String? ?? '';
            final displayMessage = customMessage.isNotEmpty
                ? '$label: $customMessage'
                : 'Successfully recognized $label!';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayMessage),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }
}

enum RecognitionMode {
  live,
  staticImage,
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
  final _messageController = TextEditingController();
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

  // Mode and Static recognition fields
  RecognitionMode _currentMode = RecognitionMode.live;
  File? _selectedImage;
  bool _isProcessingStaticImage = false;
  List<RecognitionResult> _staticResults = [];
  String? _staticErrorMessage;
  int _staticImageWidth = 1;
  int _staticImageHeight = 1;
  int _maxFacesLimit = 3;

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
    if (_currentMode == RecognitionMode.live) {
      await _initializeCamera();
      _startTimeoutTimer();
    } else {
      setState(() {
        _isInitializing = false;
        _status = 'Select an image for face recognition.';
      });
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
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
      
      if (_currentMode == RecognitionMode.live) {
        await _startImageStream();
      }

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

      final facesToProcess = faces.take(_maxFacesLimit).toList();
      final results = <RecognitionResult>[];

      for (final face in facesToProcess) {
        final croppedFace = _cropFace(rotated, face.boundingBox);
        final result = await widget.faceRecognition.recognizeFaceImage(
          croppedFace,
          face: DetectedFace(boundingBox: face.boundingBox),
        );
        results.add(result);
      }

      if (!mounted) return;

      final matchedResults = results.where((r) => r.isMatch).toList();

      if (matchedResults.isNotEmpty) {
        final firstMatch = matchedResults.first;
        _lastResult = firstMatch;

        final matchedNames = matchedResults.map((r) {
          final name = r.template?.label ?? r.template?.id ?? 'Person';
          final customMessage = r.template?.metadata['customMessage'] as String? ?? '';
          return customMessage.isNotEmpty ? '$name ("$customMessage")' : name;
        }).toList();

        final statusText = 'Matched: ${matchedNames.join(", ")}';
        final confidenceText = matchedResults
            .map((r) => '${(r.confidence * 100).toStringAsFixed(0)}%')
            .join(', ');

        _updateRecognitionStatus(statusText, confidenceText);

        if (widget.onSuccess != null) {
          await _stopImageStream();
          widget.onSuccess!(firstMatch);
        }
      } else {
        _lastResult = results.first;
        _updateRecognitionStatus(
          'No matches found (${results.length} face(s) detected).',
          _distanceToDisplay(results.first.distance),
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

  Future<void> _switchMode(RecognitionMode mode) async {
    if (_currentMode == mode) return;

    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    setState(() {
      _currentMode = mode;
      _lastResult = null;
      _isInitializing = mode == RecognitionMode.live;
      _status = mode == RecognitionMode.live ? 'Initializing...' : 'Select an image for face recognition.';
      _confidenceText = '';
    });

    if (mode == RecognitionMode.live) {
      await _initializeCamera();
      _startTimeoutTimer();
    } else {
      await _stopImageStream();
      await _controller?.dispose();
      _controller = null;
    }
  }

  Future<void> _recognizeFromStaticCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (picked == null) return;
    await _processStaticImage(File(picked.path));
  }

  Future<void> _recognizeFromStaticGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return;
    await _processStaticImage(File(picked.path));
  }

  Future<void> _processStaticImage(File imageFile) async {
    setState(() {
      _selectedImage = imageFile;
      _isProcessingStaticImage = true;
      _staticResults = [];
      _staticErrorMessage = null;
    });

    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FaceRecognitionMatchException('Failed to decode image.');
      }

      setState(() {
        _staticImageWidth = decoded.width;
        _staticImageHeight = decoded.height;
      });

      final results = await widget.faceRecognition.recognizeMultiple(
        image: imageFile,
        limit: _maxFacesLimit,
      );

      setState(() {
        _staticResults = results;
      });
    } on FaceRecognitionException catch (e) {
      setState(() {
        _staticErrorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _staticErrorMessage = 'An error occurred during recognition: $e';
      });
    } finally {
      setState(() {
        _isProcessingStaticImage = false;
      });
    }
  }

  Future<void> _registerFromCamera() async {
    final registrationData = await _askForName();
    if (registrationData == null) return;
    final name = registrationData['name']!;
    final message = registrationData['message']!;

    await _runRegistration(() async {
      if (_currentMode == RecognitionMode.live && _controller != null) {
        await _stopImageStream();
        final picture = await _controller!.takePicture();
        final savedImage = await _saveImageCopy(File(picture.path));
        await _registerFile(savedImage, name.trim(), message.trim());
        await _startImageStream();
      } else {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );
        if (picked != null) {
          final savedImage = await _saveImageCopy(File(picked.path));
          await _registerFile(savedImage, name.trim(), message.trim());
        }
      }
    });
  }

  Future<void> _registerFromGallery() async {
    final registrationData = await _askForName();
    if (registrationData == null) return;
    final name = registrationData['name']!;
    final message = registrationData['message']!;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return;

    await _runRegistration(() async {
      final savedImage = await _saveImageCopy(File(picked.path));
      await _registerFile(savedImage, name.trim(), message.trim());
    });
  }

  Future<void> _registerFile(File file, String label, String customMessage) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final result = await widget.faceRecognition.register(
      image: file,
      id: id,
      label: label,
      metadata: {
        'imagePath': file.path,
        'customMessage': customMessage,
      },
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
      if (_currentMode == RecognitionMode.live) {
        await _startImageStream();
      }
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

  Future<Map<String, String>?> _askForName() async {
    _nameController.clear();
    _messageController.clear();
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Register face'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name or ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Custom Message / Greeting',
                  helperText: 'Displayed when recognized',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = _nameController.text.trim();
                final message = _messageController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop({
                    'name': name,
                    'message': message,
                  });
                }
              },
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
    _messageController.dispose();
    _faceDetector.close();
    _controller?.dispose();
    widget.faceRecognition.dispose();
    super.dispose();
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _switchMode(RecognitionMode.live),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _currentMode == RecognitionMode.live
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_outlined, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Live Stream',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _switchMode(RecognitionMode.staticImage),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _currentMode == RecognitionMode.staticImage
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_outlined, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Attach Image',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text(
            'Max Faces Limit:',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(5, (index) {
                  final limitValue = index + 1;
                  final isSelected = _maxFacesLimit == limitValue;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$limitValue'),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _maxFacesLimit = limitValue;
                          });
                          if (_currentMode == RecognitionMode.staticImage && _selectedImage != null) {
                            _processStaticImage(_selectedImage!);
                          }
                        }
                      },
                      selectedColor: Colors.greenAccent.withValues(alpha: 0.25),
                      checkmarkColor: Colors.greenAccent,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.greenAccent : Colors.white60,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRecognitionView() {
    final controller = _controller;
    final isCameraReady = controller != null && controller.value.isInitialized;

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: isCameraReady
                ? CameraPreview(controller)
                : const ColoredBox(color: Colors.black),
          ),
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: const _CameraGradient(),
          ),
        ),
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
              width: MediaQuery.of(context).size.width * 0.85,
              fit: BoxFit.fitWidth,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _LiveStatus(
            isLoading: _isInitializing || _isRegistering,
            isSuccess: _lastResult?.isMatch ?? false,
            status: _status,
            confidenceText: _confidenceText,
          ),
        ),
      ],
    );
  }

  Widget _buildStaticRecognitionView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _selectedImage == null
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white12,
                          width: 2,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.face_retouching_natural_outlined,
                            size: 64,
                            color: Colors.white30,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No Image Selected',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Attach a photo to recognize faces',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: _staticImageWidth / _staticImageHeight,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.file(_selectedImage!, fit: BoxFit.fill),
                                ),
                                if (_staticResults.isNotEmpty)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: MultiFaceBoundingBoxPainter(
                                        results: _staticResults,
                                        imageWidth: _staticImageWidth,
                                        imageHeight: _staticImageHeight,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (_isProcessingStaticImage)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(color: Colors.greenAccent),
                                    SizedBox(height: 16),
                                    Text(
                                      'Analyzing faces...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _buildStaticStatusBox(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessingStaticImage ? null : _recognizeFromStaticCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take Photo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessingStaticImage ? null : _recognizeFromStaticGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pick Image'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.greenAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildStaticStatusBox() {
    final results = _staticResults;
    final errorMessage = _staticErrorMessage;

    if (_isProcessingStaticImage) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text(
            'Analyzing selected image...',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return const SizedBox.shrink();
    }

    final matchedResults = results.where((r) => r.isMatch).toList();
    final hasMatches = matchedResults.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: hasMatches
            ? Colors.greenAccent.withValues(alpha: 0.15)
            : Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasMatches
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.orangeAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                hasMatches ? Icons.check_circle : Icons.warning_amber_rounded,
                color: hasMatches ? Colors.greenAccent : Colors.orangeAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasMatches
                      ? 'Detected ${results.length} face(s), matched ${matchedResults.length}'
                      : 'Detected ${results.length} face(s), no matches found',
                  style: TextStyle(
                    color: hasMatches ? Colors.greenAccent : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          ...results.map((result) {
            final isMatch = result.isMatch;
            final label = result.template?.label ?? result.template?.id ?? 'Unknown';
            final customMessage = result.template?.metadata['customMessage'] as String? ?? '';
            final confidenceText = '${(result.confidence * 100).toStringAsFixed(0)}%';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isMatch ? Icons.person_outline : Icons.person_off_outlined,
                    size: 16,
                    color: isMatch ? Colors.greenAccent : Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMatch ? '$label ($confidenceText)' : 'No Match ($confidenceText)',
                          style: TextStyle(
                            color: isMatch ? Colors.white : Colors.white54,
                            fontWeight: isMatch ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        if (isMatch && customMessage.isNotEmpty)
                          Text(
                            customMessage,
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              registeredCount: _templates.length,
              onShowRegisteredFaces: _showRegisteredFaces,
            ),
            _buildModeSelector(),
            _buildLimitSelector(),
            Expanded(
              child: Stack(
                children: [
                  if (_currentMode == RecognitionMode.live)
                    _buildLiveRecognitionView()
                  else
                    _buildStaticRecognitionView(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _BottomActions(
                isBusy: _isInitializing || _isRegistering || _isProcessingStaticImage,
                onRegisterCamera: _registerFromCamera,
                onRegisterGallery: _registerFromGallery,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MultiFaceBoundingBoxPainter extends CustomPainter {
  MultiFaceBoundingBoxPainter({
    required this.results,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<RecognitionResult> results;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    for (final result in results) {
      final face = result.face;
      if (face == null) continue;

      final boundingBox = face.boundingBox;
      final double left = boundingBox.left * scaleX;
      final double top = boundingBox.top * scaleY;
      final double right = boundingBox.right * scaleX;
      final double bottom = boundingBox.bottom * scaleY;

      final isSuccess = result.isMatch;
      final color = isSuccess ? Colors.greenAccent : Colors.redAccent;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // Draw bounding box
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, bottom),
          const Radius.circular(12),
        ),
        paint,
      );

      // Draw Label
      final label = result.template?.label ?? result.template?.id ?? 'Unknown';
      final confidenceText = '${(result.confidence * 100).toStringAsFixed(0)}%';
      final textSpan = TextSpan(
        text: isSuccess ? '$label ($confidenceText)' : 'No Match ($confidenceText)',
        style: TextStyle(
          color: Colors.white,
          backgroundColor: color.withValues(alpha: 0.85),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position the label above the bounding box
      double textTop = top - textPainter.height - 4;
      if (textTop < 0) {
        textTop = top + 4; // Draw inside box if top is out of bounds
      }
      textPainter.paint(canvas, Offset(left, textTop));
    }
  }

  @override
  bool shouldRepaint(MultiFaceBoundingBoxPainter oldDelegate) {
    return oldDelegate.results != results ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
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
              'Face Recognition',
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
    final customMessage = template.metadata['customMessage'] as String?;

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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customMessage != null && customMessage.isNotEmpty) ...[
            Text(
              'Msg: "$customMessage"',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Text(
            '${template.embedding.length} values',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white38,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
