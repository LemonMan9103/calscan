import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:calscan/home/scan_result_page.dart';
import 'package:calscan/logic/recognition_service.dart';
import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF7E00);

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  final RecognitionService _recognitionService = RecognitionService();
  bool _isProcessing = false;
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_recognitionService.close());
    super.dispose();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      // load ur food model before camera can scan
      await _recognitionService.loadModel();

      if (!_recognitionService.isLoaded) {
        throw StateError(
          _recognitionService.loadError ??
              'The detection model failed to load.',
        );
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      _setError(_cameraErrorMessage(e));
    } catch (e) {
      _setError(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _errorMessage = message;
    });
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Camera access was denied. Enable it in your device settings.';
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return error.description ?? 'The camera could not be initialized.';
    }
  }

  Future<void> _handleCapture() async {
    final controller = _controller;
    if (_isProcessing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    try {
      setState(() => _isProcessing = true);
      final image = await controller.takePicture();
      final imageFile = File(image.path);
      // model detect food from captured photo
      final detections = await _recognitionService.recognizeFood(imageFile);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ScanResultPage(imageFile: imageFile, detections: detections),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) return _buildErrorState();
    if (_isInitializing || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: _kOrange)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview(_controller!)),
          _buildMealFrame(),
          _buildTopBar(),
          _buildCaptureDock(),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    final screen = MediaQuery.sizeOf(context);
    var scale = screen.aspectRatio * previewSize.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.42),
              ),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Scan Meal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealFrame() {
    return IgnorePointer(
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 292,
              height: 292,
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.86),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureDock() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 18,
      right: 18,
      bottom: 24 + bottom,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isProcessing ? 'Analyzing food...' : 'Center the meal clearly',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You can adjust portion and save after detection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 76,
              height: 76,
              child: IconButton.filled(
                tooltip: 'Capture meal',
                onPressed: _isProcessing ? null : _handleCapture,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white70,
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: _kOrange,
                          strokeWidth: 3,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_rounded,
                        color: _kOrange,
                        size: 34,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: _kOrange,
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initialize,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
