import 'dart:ui';

class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    this.trackingId,
    this.headEulerAngleX,
    this.headEulerAngleY,
    this.headEulerAngleZ,
  });

  final Rect boundingBox;
  final int? trackingId;
  final double? headEulerAngleX;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;
}
