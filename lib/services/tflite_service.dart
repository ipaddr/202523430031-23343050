import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

class TfliteService {
  Interpreter? _interpreter;
  List<String> _labels = [];

  // Derived from the loaded model input tensor.
  int _inputWidth = 224;
  int _inputHeight = 224;
  int _inputChannels = 3;
  Float32List? _inputBuffer;

  // Derived from the loaded model output tensor.
  int _outputClasses = 0;
  List<List<double>>? _outputBuffer;

  bool get isModelLoaded => _interpreter != null && _labels.isNotEmpty;
  List<String> get labels => _labels;

  /// Load the TFLite model from assets
  Future<void> loadModel() async {
    final options = InterpreterOptions()..threads = 2;
    if (Platform.isAndroid) {
      options.useNnApiForAndroid = true;
    }

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model_unquant.tflite',
        options: options,
      );
    } catch (e) {
      // Fallback: some versions of tflite_flutter resolve paths differently
      try {
        _interpreter = await Interpreter.fromAsset(
          'model_unquant.tflite',
          options: options,
        );
      } catch (_) {
        // Last fallback without custom options.
        _interpreter = await Interpreter.fromAsset('model_unquant.tflite');
      }
    }

    // Cache input tensor shape and allocate a reusable input buffer.
    final inputTensor = _interpreter!.getInputTensor(0);
    final shape = inputTensor.shape;
    // Expected NHWC: [1, height, width, channels]
    if (shape.length >= 4) {
      _inputHeight = shape[1];
      _inputWidth = shape[2];
      _inputChannels = shape[3];
    }
    _inputBuffer = Float32List(_inputWidth * _inputHeight * _inputChannels);

    // Cache output tensor classes and allocate a reusable output buffer.
    final outputTensor = _interpreter!.getOutputTensor(0);
    final outShape = outputTensor.shape;
    if (outShape.isNotEmpty) {
      _outputClasses = outShape.last;
    }
    if (_outputClasses > 0) {
      _outputBuffer = [List.filled(_outputClasses, 0.0)];
    }

    // Debug-only: helps verify model IO quickly.
    assert(() {
      final out = outputTensor;
      // ignore: avoid_print
      print(
          '[TFLite] input shape=${inputTensor.shape} type=${inputTensor.type}; output shape=${out.shape} type=${out.type}');
      return true;
    }());
  }

  /// Load labels from assets/labels.txt
  Future<void> loadLabels() async {
    final rawLabels = await rootBundle.loadString('assets/labels.txt');
    _labels = rawLabels
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final parts = line.trim().split(RegExp(r'\s+'));
          return parts.length > 1 ? parts.sublist(1).join(' ') : parts[0];
        })
        .toList();
  }

  /// Classify a camera image and return prediction result
  Map<String, dynamic>? classifyImage(
    CameraImage cameraImage,
    int sensorOrientation, {
    bool mirror = false,
  }) {
    if (_interpreter == null || _labels.isEmpty) return null;

    // Model expects a fixed-size input; keep it resilient.
    final inputW = _inputWidth;
    final inputH = _inputHeight;
    final inputC = _inputChannels;
    final inputBuffer = _inputBuffer;
    if (inputBuffer == null || inputC != 3) return null;

    final int classes = _outputClasses > 0 ? _outputClasses : _labels.length;
    if (classes <= 0) return null;

    try {
      final inputTensor = _buildInputTensorFromCameraImage(
        cameraImage,
        sensorOrientation,
        inputBuffer,
        inputW,
        inputH,
        mirror: mirror,
      );
      if (inputTensor == null) return null;

        // Output tensor [1, num_classes]
        final output = (_outputBuffer != null && _outputBuffer!.isNotEmpty && _outputBuffer![0].length == classes)
          ? _outputBuffer!
          : [List.filled(classes, 0.0)];

      // Run inference
      _interpreter!.run(inputTensor, output);

      // Find top prediction
      final probabilities = output[0];
      int maxIdx = 0;
      double maxProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIdx = i;
        }
      }

      return {
        'label': maxIdx < _labels.length ? _labels[maxIdx] : 'kelas_$maxIdx',
        'confidence': maxProb,
        'index': maxIdx,
      };
    } catch (e) {
      return null;
    }
  }

  Object? _buildInputTensorFromCameraImage(
    CameraImage cameraImage,
    int sensorOrientation,
    Float32List inputBuffer,
    int outW,
    int outH, {
    required bool mirror,
  }) {
    // Currently optimized for Android YUV420 stream.
    if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      _fillInputFromYuv420(
        cameraImage,
        sensorOrientation,
        inputBuffer,
        outW,
        outH,
        mirror: mirror,
      );
      return inputBuffer.reshape([1, outH, outW, 3]);
    }

    // Fallback for other formats (e.g., iOS BGRA8888).
    final image = _convertCameraImage(cameraImage);
    if (image == null) return null;

    img.Image oriented = image;
    if (sensorOrientation == 90) {
      oriented = img.copyRotate(image, angle: 90);
    } else if (sensorOrientation == 270) {
      oriented = img.copyRotate(image, angle: -90);
    }

    // Center-crop to square first to reduce background influence.
    final cropSize = oriented.width < oriented.height ? oriented.width : oriented.height;
    final cropX = ((oriented.width - cropSize) / 2).round();
    final cropY = ((oriented.height - cropSize) / 2).round();
    final cropped = img.copyCrop(
      oriented,
      x: cropX,
      y: cropY,
      width: cropSize,
      height: cropSize,
    );

    final resized = img.copyResize(cropped, width: outW, height: outH);
    int idx = 0;
    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        final px = mirror ? (outW - 1 - x) : x;
        final pixel = resized.getPixel(px, y);
        inputBuffer[idx++] = pixel.r / 255.0;
        inputBuffer[idx++] = pixel.g / 255.0;
        inputBuffer[idx++] = pixel.b / 255.0;
      }
    }
    return inputBuffer.reshape([1, outH, outW, 3]);
  }

  void _fillInputFromYuv420(
    CameraImage image,
    int sensorOrientation,
    Float32List out,
    int outW,
    int outH, {
    required bool mirror,
  }) {
    final srcW = image.width;
    final srcH = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    final int rot = sensorOrientation % 360;
    final bool swapWH = rot == 90 || rot == 270;
    final int orientedW = swapWH ? srcH : srcW;
    final int orientedH = swapWH ? srcW : srcH;

    // Center square crop in oriented space.
    final int cropSize = orientedW < orientedH ? orientedW : orientedH;
    final double cropX0 = (orientedW - cropSize) / 2.0;
    final double cropY0 = (orientedH - cropSize) / 2.0;

    int idx = 0;
    for (int y = 0; y < outH; y++) {
      final double oy = cropY0 + (y + 0.5) * cropSize / outH;
      for (int x = 0; x < outW; x++) {
        final int xm = mirror ? (outW - 1 - x) : x;
        final double ox = cropX0 + (xm + 0.5) * cropSize / outW;

        int sx;
        int sy;

        if (rot == 90) {
          // Source rotated 90° clockwise => oriented(x,y) = (H-1-sy, sx)
          sx = oy.floor();
          sy = (srcH - 1 - ox.floor());
        } else if (rot == 270) {
          // Source rotated 90° counter-clockwise => oriented(x,y) = (sy, W-1-sx)
          sx = (srcW - 1 - oy.floor());
          sy = ox.floor();
        } else if (rot == 180) {
          sx = (srcW - 1 - ox.floor());
          sy = (srcH - 1 - oy.floor());
        } else {
          // rot == 0
          sx = ox.floor();
          sy = oy.floor();
        }

        if (sx < 0) sx = 0;
        if (sy < 0) sy = 0;
        if (sx >= srcW) sx = srcW - 1;
        if (sy >= srcH) sy = srcH - 1;

        final int yIndex = sy * yRowStride + sx;
        final int uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;

        final int yVal = yBytes[yIndex];
        final int uVal = uBytes[uvIndex];
        final int vVal = vBytes[uvIndex];

        final int u = uVal - 128;
        final int v = vVal - 128;

        int r = (yVal + 1.370705 * v).round();
        int g = (yVal - 0.337633 * u - 0.698001 * v).round();
        int b = (yVal + 1.732446 * u).round();

        if (r < 0) r = 0;
        if (g < 0) g = 0;
        if (b < 0) b = 0;
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;

        out[idx++] = r / 255.0;
        out[idx++] = g / 255.0;
        out[idx++] = b / 255.0;
      }
    }
  }

  img.Image? _convertCameraImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA(cameraImage);
      }
    } catch (_) {}
    return null;
  }

  img.Image _convertYUV420(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final result = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yIndex = row * yRowStride + col;
        final uvIndex = (row ~/ 2) * uvRowStride + (col ~/ 2) * uvPixelStride;

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
        int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).round().clamp(0, 255);
        int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

        result.setPixelRgb(col, row, r, g, b);
      }
    }
    return result;
  }

  img.Image _convertBGRA(CameraImage image) {
    final bytes = image.planes[0].bytes;
    final width = image.width;
    final height = image.height;
    final result = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final idx = (row * width + col) * 4;
        result.setPixelRgb(col, row, bytes[idx + 2], bytes[idx + 1], bytes[idx]);
      }
    }
    return result;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
