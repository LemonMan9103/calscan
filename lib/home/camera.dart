import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:calscan/logic/recognition_service.dart';
import 'package:calscan/home/scan_result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final RecognitionService _recognitionService = RecognitionService();
  bool _isProcessing = false;


  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _recognitionService.loadModel();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _recognitionService.close();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    if (_isProcessing) return;

    try {
      setState(() => _isProcessing = true);

      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      final imageFile = File(image.path);

      final result = _recognitionService.recognizeFood(imageFile);

      if (mounted) {
        // Always navigate to the result page — it handles both detected & not-detected states
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScanResultPage(
              imageFile: imageFile,
              result: result,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during capture: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && _controller != null) {
            return Stack(
              children: [
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
                
                // Overlay for panels explanation: Framing
                _buildCameraOverlay(),

                // Back Button
                Positioned(
                  top: 40,
                  left: 20,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Capture Controls
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        _isProcessing ? 'Analyzing Food...' : 'Align food within the frame',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: _handleCapture,
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
            );
          } else {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          }
        },
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

