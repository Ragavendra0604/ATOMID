import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/core/utils/platform_io.dart';

/// A bottom sheet that presents share / download / print options for a PDF.
///
/// The "Share" action writes the PDF to the app's cache directory and hands it
/// to `share_plus` via [SharePlus.instance.share]. The cache directory is
/// served through the plugin's FileProvider, so the native OS share sheet
/// appears with all available apps (WhatsApp, Gmail, Bluetooth, etc.).
///
/// This avoids [Printing.sharePdf] which opens a PDF viewer / browser on many
/// Android devices instead of the actual share intent.
class ShareBottomSheet extends StatefulWidget {
  /// The raw PDF bytes to share.
  final Uint8List pdfBytes;

  /// The base file name (without extension) for saving and sharing.
  final String fileName;

  /// A one-line message attached to the share (e.g. invoice number + total).
  final String shareText;

  /// If non-null, the page format used for the print dialog.
  final PdfPageFormat? printPageFormat;

  const ShareBottomSheet({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.shareText,
    this.printPageFormat,
  });

  /// Shows the bottom sheet and returns when it's dismissed.
  static Future<void> show({
    required BuildContext context,
    required Uint8List pdfBytes,
    required String fileName,
    required String shareText,
    PdfPageFormat? printPageFormat,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShareBottomSheet(
        pdfBytes: pdfBytes,
        fileName: fileName,
        shareText: shareText,
        printPageFormat: printPageFormat,
      ),
    );
  }

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  bool _busy = false;

  // ── Share via native OS share sheet ─────────────────────────────────────

  Future<void> _onShare() async {
    setState(() => _busy = true);
    try {
      final safeName = ExportService.safeFileName(widget.fileName);

      if (PlatformIo.isWindows || PlatformIo.isMacOS || PlatformIo.isLinux) {
        // Desktop: share_plus file sharing silently fails. Save the PDF to
        // the documents folder and open it with the system's default viewer
        // so the user can share/print/email from there.
        final file = await ExportService.exportPdfBytes(
          widget.pdfBytes,
          widget.fileName,
        );

        if (PlatformIo.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', file.path]);
        } else if (PlatformIo.isMacOS) {
          await Process.run('open', [file.path]);
        } else {
          await Process.run('xdg-open', [file.path]);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Opened ${file.path}')));
        Navigator.pop(context);
      } else {
        // Mobile (Android / iOS): write to cache dir and use share_plus.
        // The cache directory is served through share_plus's FileProvider as
        // content:// URIs, which is what the Android share intent needs.
        final cacheDir = await getTemporaryDirectory();
        final tempFile = File('${cacheDir.path}/$safeName.pdf');
        await tempFile.writeAsBytes(widget.pdfBytes, flush: true);

        if (!mounted) return;

        // Anchor rect for iPad share popover (required on iOS 26+).
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null;

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path, mimeType: 'application/pdf')],
            text: widget.shareText,
            sharePositionOrigin: origin,
          ),
        );

        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Save PDF locally ──────────────────────────────────────────────────

  Future<void> _onDownload() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ExportService.exportPdfBytes(
        widget.pdfBytes,
        widget.fileName,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved to ${file.path}'),
          action: PlatformIo.isWindows
              ? SnackBarAction(
                  label: 'Show in Folder',
                  onPressed: () => _openFolder(file.path),
                )
              : null,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────

  Future<void> _onPrint() async {
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => widget.pdfBytes,
        name: widget.fileName,
        format: widget.printPageFormat ?? PdfPageFormat.a4,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFolder(String path) {
    if (PlatformIo.isWindows) {
      Process.run('explorer.exe', ['/select,', path]);
    } else {
      Clipboard.setData(ClipboardData(text: path));
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Text(
              'Share Document',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.shareText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action tiles
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShareOption(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    color: colorScheme.primary,
                    onTap: _onShare,
                  ),
                  _ShareOption(
                    icon: Icons.download_rounded,
                    label: 'Save PDF',
                    color: colorScheme.tertiary,
                    onTap: _onDownload,
                  ),
                  _ShareOption(
                    icon: Icons.print_rounded,
                    label: 'Print',
                    color: colorScheme.secondary,
                    onTap: _onPrint,
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// A single circular option in the share sheet.
class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}