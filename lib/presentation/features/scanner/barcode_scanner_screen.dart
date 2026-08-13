import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';
import 'package:atomid/presentation/features/price_tag/price_tag_screen.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  MobileScannerController? _scannerController;
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null) {
        setState(() => _isScanning = false);
        // Stop the camera safely before navigating to prevent BufferQueue abandoned errors
        await _scannerController?.stop();
        if (mounted) {
          _handleBarcodeFound(code);
        }
      }
    }
  }

  void _handleBarcodeFound(String barcode) {
    final repo = ref.read(storageRepositoryProvider);
    final product = repo.getProductByBarcode(barcode);

    if (product != null) {
      final variant = product.variants.firstWhere((v) => v.barcode == barcode);

      // Log history
      repo.saveHistory(
        ActionHistory(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          barcode: barcode,
          productName: product.productName,
          action: 'Barcode Scanned',
          date: DateTime.now(),
        ),
      );

      // Navigate to price tag
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PriceTagScreen(product: product, initialVariant: variant),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AdaptiveDialog(
          title: const Text('Product Not Found'),
          content: Text('No product found with barcode: $barcode'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _scannerController?.start();
                if (mounted) {
                  setState(() => _isScanning = true);
                }
              },
              child: const Text('Scan Again'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.yellow),
            onPressed: () => _scannerController!.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController!.switchCamera(),
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          // Cleanly stop the camera before destroying the view
          await _scannerController?.stop();
          if (context.mounted) {
            Navigator.pop(context, result);
          }
        },
        child: MobileScanner(
          controller: _scannerController!,
          onDetect: _onDetect,
        ),
      ),
    );
  }
}
