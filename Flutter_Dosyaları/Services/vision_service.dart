import 'dart:io'; 
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VisionService {
  ObjectDetector? _objectDetector;
  bool isDetecting = false;
  bool isEnabled = true; // Nesne tanıma özelliği açık mı?

  void init() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<List<DetectedObject>> processFrame(CameraImage image, CameraDescription camera) async {
    // Servis kapalıysa veya zaten işlem yapılıyorsa atla
    if (!isEnabled || isDetecting || _objectDetector == null) return [];
    
    isDetecting = true;

    try {
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage == null) return [];
      
      // İşleme
      final objects = await _objectDetector!.processImage(inputImage);
      
      return objects;
    } catch (e) {
      print("Vision Service Hatası: $e");
      return [];
    } finally {
      isDetecting = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    // 1. ROTASYON HESAPLAMA
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    
    if (Platform.isAndroid) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    // Fallback: Eğer null ise 90 derece varsay
    rotation ??= InputImageRotation.rotation90deg;

    // 2. FORMAT KONTROLÜ
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    
    // Format desteklenmiyorsa veya null ise işlem yapma
    if (format == null) return null;

    // --- SİLİNEN SATIR: Buradaki 'onFaceDetected' değişkeni gereksizdi ---

    // 3. BYTE BİRLEŞTİRME (WriteBuffer kullanımı en güvenli yoldur)
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // 4. InputImage OLUŞTURMA
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow, 
      ),
    );
  }

  void dispose() {
    _objectDetector?.close();
  }
}