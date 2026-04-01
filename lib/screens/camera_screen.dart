import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:collection';
import '../services/tflite_service.dart';
import '../widgets/result_overlay.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  final TfliteService _tfliteService = TfliteService();

  int _selectedCameraIdx = 0;
  bool _isDetecting = false;
  bool _isProcessing = false;
  bool _isModelLoaded = false;
  bool _isCameraReady = false;
  String? _errorMessage;

  // Prediction results
  String? _currentLabel;
  double _currentConfidence = 0.0;
  final Queue<_PredictionSample> _recentPredictions = Queue<_PredictionSample>();

  // Adaptive throttle to reduce dropped frames/GC pressure.
  static const int _minInferenceIntervalMs = 220;
  static const int _maxInferenceIntervalMs = 550;
  int _inferenceIntervalMs = 280;
  static const int _predictionWindowSize = 7;
  static const int _minVotesForStable = 3;
  static const double _minConfidenceForVote = 0.45;
  int _lastInferenceTimeMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadModel();
    await _initCamera();
  }

  Future<void> _loadModel() async {
    try {
      await _tfliteService.loadModel();
      await _tfliteService.loadLabels();
      if (mounted) {
        setState(() => _isModelLoaded = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Gagal memuat model: $e');
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'Tidak ada kamera yang tersedia');
        return;
      }

      // Prefer front camera
      _selectedCameraIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_selectedCameraIdx == -1) _selectedCameraIdx = 0;

      await _startCamera(_cameras[_selectedCameraIdx]);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Gagal inisialisasi kamera: $e');
      }
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final prevController = _controller;
    final newController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    // Dispose old controller after creating new one
    if (prevController != null) {
      setState(() {
        _isCameraReady = false;
        _controller = null;
      });
      await prevController.dispose();
    }

    try {
      await newController.initialize();
      try {
        await newController.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await newController.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _controller = newController;
          _isCameraReady = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Izin kamera ditolak atau error: $e');
      }
    }
  }

  void _toggleDetection() {
    if (_isDetecting) {
      _stopDetection();
    } else {
      _startDetection();
    }
  }

  void _startDetection() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_isModelLoaded) return;

    _recentPredictions.clear();
    _inferenceIntervalMs = 280;
    _lastInferenceTimeMs = 0;
    setState(() => _isDetecting = true);
    _controller!.startImageStream(_onCameraFrame);
  }

  void _stopDetection() {
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _recentPredictions.clear();
    setState(() {
      _isDetecting = false;
      _currentLabel = null;
      _currentConfidence = 0.0;
    });
  }

  void _onCameraFrame(CameraImage image) {
    if (!_isModelLoaded) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing || (now - _lastInferenceTimeMs) < _inferenceIntervalMs) {
      return;
    }

    _isProcessing = true;
    _lastInferenceTimeMs = now;
    final sw = Stopwatch()..start();

    try {
      final camera = _cameras[_selectedCameraIdx];
      final result = _tfliteService.classifyImage(
        image,
        camera.sensorOrientation,
        mirror: camera.lensDirection == CameraLensDirection.front,
      );

      if (result != null) {
        final label = result['label'] as String;
        final confidence = (result['confidence'] as double);

        if (confidence >= _minConfidenceForVote) {
          _recentPredictions.addLast(_PredictionSample(label, confidence));
          while (_recentPredictions.length > _predictionWindowSize) {
            _recentPredictions.removeFirst();
          }
        }

        final stable = _computeStablePrediction();
        if (stable != null && mounted) {
          final labelChanged = _currentLabel != stable.label;
          final confidenceChanged = (_currentConfidence - stable.confidence).abs() > 0.03;
          if (labelChanged || confidenceChanged) {
            setState(() {
              _currentLabel = stable.label;
              _currentConfidence = stable.confidence;
            });
          }
        }
      }
    } finally {
      sw.stop();
      final int suggested = (sw.elapsedMilliseconds * 1.4).round();
      _inferenceIntervalMs = suggested.clamp(_minInferenceIntervalMs, _maxInferenceIntervalMs);
      _isProcessing = false;
    }
  }

  _PredictionSample? _computeStablePrediction() {
    if (_recentPredictions.isEmpty) return null;

    final Map<String, int> votes = <String, int>{};
    final Map<String, double> confSums = <String, double>{};

    for (final sample in _recentPredictions) {
      votes[sample.label] = (votes[sample.label] ?? 0) + 1;
      confSums[sample.label] = (confSums[sample.label] ?? 0.0) + sample.confidence;
    }

    String? bestLabel;
    int bestVotes = 0;
    double bestAvgConfidence = 0.0;

    votes.forEach((label, count) {
      final avg = (confSums[label] ?? 0.0) / count;
      final isBetter = count > bestVotes || (count == bestVotes && avg > bestAvgConfidence);
      if (isBetter) {
        bestLabel = label;
        bestVotes = count;
        bestAvgConfidence = avg;
      }
    });

    if (bestLabel == null || bestVotes < _minVotesForStable) {
      return null;
    }

    return _PredictionSample(bestLabel!, bestAvgConfidence);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    // Stop detection before switching
    if (_isDetecting) _stopDetection();

    _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    await _startCamera(_cameras[_selectedCameraIdx]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      if (_isDetecting) _stopDetection();
      _controller?.dispose();
      _controller = null;
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isDetecting) {
      try {
        _controller?.stopImageStream();
      } catch (_) {}
    }
    _controller?.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? _buildErrorView()
          : SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Klasifikasi Ekspresi Wajah',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildCameraPreview(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildResultPanel(),
                  ),
                  const SizedBox(height: 12),
                  _buildBottomControls(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  Widget _buildCameraPreview() {
    final borderRadius = BorderRadius.circular(24);

    if (!_isCameraReady || _controller == null || !_controller!.value.isInitialized) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: const Color(0xFF111111),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    final previewSize = _controller!.value.previewSize!;
    final cameraAspect = previewSize.height / previewSize.width;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: const Color(0xFF111111),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: cameraAspect,
              child: CameraPreview(_controller!),
            ),
          ),
          if (!_isModelLoaded)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF6C63FF)),
                    SizedBox(height: 12),
                    Text(
                      'Memuat model...',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: (_currentLabel != null && _isDetecting)
          ? ResultOverlay(
              key: ValueKey('result-${_currentLabel!}'),
              label: _currentLabel!,
              confidence: _currentConfidence,
            )
          : Container(
              key: const ValueKey('hint'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(
                    _isDetecting ? Icons.hourglass_top_rounded : Icons.info_outline,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isDetecting
                          ? 'Menunggu prediksi stabil...'
                          : 'Tekan tombol Play untuk memulai deteksi ekspresi',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Switch camera button
          _buildControlButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Switch',
            onTap: _cameras.length > 1 ? _switchCamera : null,
          ),
          // Start/Stop detection button
          _buildDetectionButton(),
          // Placeholder for symmetry
          _buildControlButton(
            icon: _isDetecting ? Icons.visibility : Icons.visibility_off,
            label: _isDetecting ? 'Aktif' : 'Mati',
            onTap: null,
            isStatus: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionButton() {
    final bool canStart = _isModelLoaded && _isCameraReady;
    return GestureDetector(
      onTap: canStart ? _toggleDetection : null,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _isDetecting
              ? const LinearGradient(
                  colors: [Color(0xFFE53935), Color(0xFFFF7043)],
                )
              : canStart
                  ? const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF03DAC6)],
                    )
                  : LinearGradient(
                      colors: [Colors.grey.shade700, Colors.grey.shade600],
                    ),
          boxShadow: [
            BoxShadow(
              color: _isDetecting
                  ? const Color(0xFFE53935).withValues(alpha: 0.4)
                  : const Color(0xFF6C63FF).withValues(alpha: 0.3),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          _isDetecting ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isStatus = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isStatus
                  ? (_isDetecting
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.1))
                  : Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(
              icon,
              color: onTap != null || isStatus
                  ? Colors.white
                  : Colors.white38,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _errorMessage = null);
                _initializeApp();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionSample {
  final String label;
  final double confidence;

  _PredictionSample(this.label, this.confidence);
}
