import 'package:flutter/material.dart';
import 'package:atomid/core/utils/ids.dart';
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

    // Resolved through the barcode index, so the variant should always be
    // there — but an unguarded `firstWhere` turns "should" into a StateError
    // that crashes the scanner mid-shift. A stale index is exactly the state
    // `auditDerivedState` exists to report, and the cashier's recovery from
    // it is the same as for an unknown barcode: say so, and offer another
    // scan.
    final matching = product?.variants.where((v) => v.barcode == barcode);
    final variant = (matching == null || matching.isEmpty)
        ? null
        : matching.first;

    if (product != null && variant != null) {
      // Log history
      repo.saveHistory(
        ActionHistory(
          // Not a timestamp: two scans inside one millisecond shared a key
          // and the second silently replaced the first. See `Ids`.
          id: Ids.generate(),
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
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flash_on, color: Colors.yellow),
            onPressed: () => _scannerController!.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
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
