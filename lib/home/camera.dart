import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:calscan/home/scan_result_page.dart';
import 'package:calscan/logic/recognition_service.dart';
import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_recognitionService.close());
    super.dispose();
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
      final detections = await _recognitionService.recognizeFood(imageFile);

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ScanResultPage(imageFile: imageFile, detections: detections),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
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
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF7E00))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          _buildCameraOverlay(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isProcessing
                      ? 'Analyzing food...'
                      : 'Align food within the frame',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 30),
                GestureDetector(
                  onTap: _isProcessing ? null : _handleCapture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                    ),
                    child: Center(
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Container(
                              height: 60,
                              width: 60,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                color: Color(0xFFFF7E00),
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

  Widget _buildCameraOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.5),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
