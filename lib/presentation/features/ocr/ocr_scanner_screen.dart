import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:atomid/presentation/features/products/product_form_screen.dart';

class OcrScannerScreen extends ConsumerStatefulWidget {
  const OcrScannerScreen({super.key});

  @override
  ConsumerState<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends ConsumerState<OcrScannerScreen> {
  ImagePicker? _picker;
  TextRecognizer? _textRecognizer;

  @override
  void initState() {
    super.initState();
    _picker = ImagePicker();
    if (!kIsWeb) {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    }
  }

  bool _isProcessing = false;
  String _extractedText = '';

  String? _parsedPrice;
  String? _parsedCode;
  String? _parsedSize;

  @override
  void dispose() {
    _textRecognizer?.close();
    super.dispose();
  }

  Future<void> _scanTag(ImageSource source) async {
    try {
      if (_picker == null) return;
      final XFile? image = await _picker!.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _isProcessing = true;
        _extractedText = '';
        _parsedPrice = null;
        _parsedCode = null;
        _parsedSize = null;
      });

      if (kIsWeb || _textRecognizer == null) {
        throw Exception('OCR is not supported on Web');
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer!.processImage(
        inputImage,
      );

      _extractedText = recognizedText.text;
      _parseText(_extractedText);
    } catch (e) {
      debugPrint('OCR error: $e');
      _extractedText =
          'Unable to read tag. Please try again with a clearer image.';
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _parseText(String text) {
    // Simple regex parsing rules
    final lines = text.split('\n');
    for (var line in lines) {
      line = line.trim();

      // Price: look for ₹ or Rs followed by digits
      if (RegExp(r'(₹|Rs\.?)\s*(\d+)').hasMatch(line)) {
        final match = RegExp(r'(₹|Rs\.?)\s*(\d+)').firstMatch(line);
        _parsedPrice = match?.group(2);
      }

      // Code/Barcode: look for alphanumeric strings typical for barcodes (ATDM369)
      if (RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(line) && !line.contains('MRP')) {
        _parsedCode = line;
      }

      // Size
      if (['S', 'M', 'L', 'XL', 'XXL'].contains(line.toUpperCase())) {
        _parsedSize = line.toUpperCase();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Tag Reader')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _scanTag(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _scanTag(ImageSource.gallery),
                  icon: const Icon(Icons.image),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isProcessing) const CircularProgressIndicator(),
            if (!_isProcessing && _extractedText.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Extracted Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const Divider(),
                      _buildExtractedRow('Code/Barcode', _parsedCode),
                      _buildExtractedRow(
                        'Price',
                        _parsedPrice != null ? '₹$_parsedPrice' : null,
                      ),
                      _buildExtractedRow('Size', _parsedSize),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductFormScreen(
                                  initialCode: _parsedCode,
                                  initialPrice: _parsedPrice,
                                  initialSize: _parsedSize,
                                ),
                              ),
                            );
                          },
                          child: const Text('Review & Create Product'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Raw OCR Text:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.grey.withValues(alpha: 0.1),
                child: Text(_extractedText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value ?? 'Not found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: value != null ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
