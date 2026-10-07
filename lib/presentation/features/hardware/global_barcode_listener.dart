import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/hardware/barcode_scanner_service.dart';

/// A global widget that listens for keyboard events.
/// Barcode scanners simulating Keyboard HID will type characters extremely fast.
/// We measure the time between keystrokes. If multiple characters arrive very fast
/// and end with an 'Enter', we consider it a scan.
class GlobalBarcodeListener extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalBarcodeListener({super.key, required this.child});

  @override
  ConsumerState<GlobalBarcodeListener> createState() =>
      _GlobalBarcodeListenerState();
}

class _GlobalBarcodeListenerState extends ConsumerState<GlobalBarcodeListener> {
  final FocusNode _focusNode = FocusNode();
  String _buffer = '';
  DateTime? _lastKeystrokeTime;

  // Most hardware scanners send chars < 30ms apart. Humans type much slower.
  static const int _barcodeMaxCharIntervalMs = 50;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final now = DateTime.now();

    // Check if the keystroke sequence timed out (meaning it's just slow human typing)
    if (_lastKeystrokeTime != null) {
      if (now.difference(_lastKeystrokeTime!).inMilliseconds.abs() >
          _barcodeMaxCharIntervalMs) {
        _buffer =
            ''; // Reset buffer because typing was too slow to be a scanner
      }
    }

    _lastKeystrokeTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.isNotEmpty) {
        // Dispatch the complete barcode sequence
        ref.read(barcodeScannerServiceProvider).processScannedBarcode(_buffer);
        _buffer = '';
      }
    } else {
      final char = event.character;
      if (char != null) {
        if (_buffer.length < 256) {
          _buffer += char;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
