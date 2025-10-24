import 'dart:ui';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class DetectionResult {
  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  final String label;
  final double confidence;
  final Rect boundingBox;
}

class DetectionEngine {
  DetectionEngine._();

  static final DetectionEngine instance = DetectionEngine._();

  final FaceDetector _faceDetector = GoogleMlKit.vision.faceDetector(
    FaceDetectorOptions(
      enableContours: false,
      enableClassification: true,
      enableTracking: true,
    ),
  );

  final ObjectDetector _objectDetector = GoogleMlKit.vision.objectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  Future<DetectionResult?> analyzeImage(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final tempFile = await _writeTemp(bytes);
    try {
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        return DetectionResult(
          label: 'Rostro detectado',
          confidence: face.smilingProbability ?? 0.85,
          boundingBox: face.boundingBox,
        );
      }

      final objects = await _objectDetector.processImage(inputImage);
      if (objects.isNotEmpty) {
        final obj = objects.first;
        final label = obj.labels.isNotEmpty
            ? obj.labels.first.text
            : 'Objeto detectado';
        final confidence = obj.labels.isNotEmpty
            ? obj.labels.first.confidence
            : 0.7;
        return DetectionResult(
          label: label,
          confidence: confidence,
          boundingBox: obj.boundingBox,
        );
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
    return null;
  }

  static Future<File> _writeTemp(Uint8List bytes) async {
    final file = await File(
      '${Directory.systemTemp.path}/'
      'detect_${DateTime.now().millisecondsSinceEpoch}.jpg',
    ).create();
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static bool isSimilar(DetectionResult a, DetectionResult b) {
    final intersection = a.boundingBox.intersect(b.boundingBox);
    if (intersection.isEmpty) return false;

    final unionArea =
        a.boundingBox.width * a.boundingBox.height +
        b.boundingBox.width * b.boundingBox.height -
        intersection.width * intersection.height;
    if (unionArea <= 0) return false;

    final iou = (intersection.width * intersection.height) / unionArea;
    return iou >= 0.45;
  }
}
