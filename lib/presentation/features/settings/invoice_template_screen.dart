import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/domain/invoice_template.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Lets the shop choose the one invoice design it prints.
///
/// Each card shows the template rendered from the same sample bill, so the
/// choice is made by looking at the document rather than by reading a name.
/// The choice is presentation only: every template renders the same stored
/// sale, so switching between them cannot change a quantity, a rate, the
/// taxable value, the GST charged or the total payable.
class InvoiceTemplateScreen extends ConsumerStatefulWidget {
  const InvoiceTemplateScreen({super.key});

  @override
  ConsumerState<InvoiceTemplateScreen> createState() =>
      _InvoiceTemplateScreenState();
}

class _InvoiceTemplateScreenState
    extends ConsumerState<InvoiceTemplateScreen> {
  /// One rasterised first page per template. Absent while it renders, and
  /// absent for good if rasterising is unavailable on this platform — the
  /// card then falls back to a drawn impression of the layout rather than
  /// showing nothing.
  final Map<InvoiceTemplate, Uint8List> _previews = {};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: the providers are read, not watched, and the
    // sample renders in the background while the list is already on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _renderPreviews());
  }

  Future<void> _renderPreviews() async {
    final settings = ref.read(settingsProvider);
    final company = ref.read(companyProvider);
    final invoiceSettings = ref.read(invoiceSettingsProvider);
    final sample = _sampleSale();

    for (final template in InvoiceTemplate.values) {
      try {
        final pdf = await ExportService.generateInvoiceForTemplate(
          sample,
          settings,
          company,
          invoiceSettings,
          template: template,
          pageFormat: template.isThermal ? null : PdfPageFormat.a4,
        );
        final bytes = await pdf.save();
        await for (final page in Printing.raster(
          bytes,
          pages: const [0],
          dpi: 48,
        )) {
          final png = await page.toPng();
          if (!mounted) return;
          setState(() => _previews[template] = png);
          break;
        }
      } catch (_) {
        // A platform without a PDF rasteriser must not take the picker down
        // with it. The drawn impression stands in.
        if (!mounted) return;
        setState(() => _failed = true);
      }
    }

    // Raster yields nothing at all for a document it cannot handle, without
    // throwing — the same trap `exportPng` hit. Without this the placeholder
    // would spin for ever on a preview that is never coming.
    if (!mounted) return;
    if (_previews.length < InvoiceTemplate.values.length) {
      setState(() => _failed = true);
    }
  }

  Future<void> _select(InvoiceTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = ref.read(settingsProvider);
    await ref
        .read(storageRepositoryProvider)
        .saveSettings(settings.copyWith(invoiceTemplate: template.id));
    messenger.showSnackBar(
      SnackBar(
        content: Text('${template.label} will now print on every bill.'),
      ),
    );
  }

  /// Opens the sample at full size, with the same paper the template prints
  /// on, so the shop can read the whole document before committing.
  void _openFullPreview(InvoiceTemplate template) {
    final settings = ref.read(settingsProvider);
    final company = ref.read(companyProvider);
    final invoiceSettings = ref.read(invoiceSettingsProvider);
    final sample = _sampleSale();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (previewContext) => Scaffold(
          appBar: AppBar(title: Text('${template.label} — sample')),
          body: Column(
            children: [
              Expanded(
                child: PdfPreview(
                  build: (format) => ExportService.generateInvoiceForTemplate(
                    sample,
                    settings,
                    company,
                    invoiceSettings,
                    template: template,
                    pageFormat: format,
                  ).then((pdf) => pdf.save()),
                  allowPrinting: false,
                  allowSharing: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  initialPageFormat: template.isThermal
                      ? (settings.thermalReceiptSize == '58mm'
                            ? PdfPageFormat.roll57
                            : PdfPageFormat.roll80)
                      : PdfPageFormat.a4,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await _select(template);
                        if (previewContext.mounted) {
                          Navigator.pop(previewContext);
                        }
                      },
                      child: Text('Use ${template.label}'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final selected = InvoiceTemplate.fromId(settings.invoiceTemplate);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Template')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Every bill prints in the design chosen here. There is no '
            'per-sale choice at the counter, so the shop issues the same '
            'document every time.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Each preview is the same sample bill — three GST rates, a '
            'walk-in customer. The template changes the layout only; the '
            'amounts and GST are identical on every one.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              'Previews could not be drawn on this device. Tap a template to '
              'open the full sample instead.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final template in InvoiceTemplate.values)
            _TemplateCard(
              template: template,
              isSelected: template == selected,
              preview: _previews[template],
              isLoading: !_failed,
              onSelect: () => _select(template),
              onOpenPreview: () => _openFullPreview(template),
            ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final InvoiceTemplate template;
  final bool isSelected;
  final Uint8List? preview;
  final bool isLoading;
  final VoidCallback onSelect;
  final VoidCallback onOpenPreview;

  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.preview,
    required this.isLoading,
    required this.onSelect,
    required this.onOpenPreview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpenPreview,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewPane(
                template: template,
                preview: preview,
                isLoading: isLoading,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            template.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Selected',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.description,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: onOpenPreview,
                          icon: const Icon(Icons.zoom_in, size: 18),
                          label: const Text('Full preview'),
                        ),
                        if (!isSelected)
                          OutlinedButton(
                            onPressed: onSelect,
                            child: const Text('Use this template'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rendered first page, once it is ready. Until then — and on a platform
/// that cannot rasterise a PDF — a drawn impression of the layout, so the
/// card is never an empty box.
class _PreviewPane extends StatelessWidget {
  final InvoiceTemplate template;
  final Uint8List? preview;
  final bool isLoading;

  const _PreviewPane({
    required this.template,
    required this.preview,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRoll = template.isThermal;
    final width = isRoll ? 64.0 : 92.0;
    const height = 124.0;

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: preview == null
          ? _Placeholder(template: template, isLoading: isLoading)
          : Image.memory(
              preview!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final InvoiceTemplate template;
  final bool isLoading;

  const _Placeholder({required this.template, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outlineVariant;
    final accent = theme.colorScheme.primary.withValues(alpha: 0.35);

    Widget bar(double widthFactor, {bool strong = false}) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: 3,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: strong ? accent : line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(0.7, strong: true),
          bar(0.45),
          const SizedBox(height: 4),
          bar(1),
          bar(1),
          if (!template.isThermal) bar(1),
          const SizedBox(height: 4),
          bar(0.6, strong: true),
          if (template != InvoiceTemplate.simpleRetail)
            bar(0.6, strong: true),
          bar(0.4, strong: true),
          const Spacer(),
          if (isLoading)
            const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}

/// A throwaway bill used only to draw the previews.
///
/// Never saved and never given an id that could collide with a real sale. It
/// deliberately carries three GST rates so the rate-wise summary appears, and
/// an HSN on every line, because both print on the real document.
Sale _sampleSale() {
  SaleItem line(String name, double taxable, double rate, double half) {
    return SaleItem(
      productId: 'SAMPLE',
      productName: name,
      variantBarcode: 'SAMPLE',
      variantSize: 'M',
      price: taxable,
      quantity: 1,
      total: taxable + half + half,
      hsn: '6109',
      uqc: 'PCS',
      gstRate: rate,
      gstTreatment: 'taxable',
      taxableValue: taxable,
      cgstAmount: half,
      sgstAmount: half,
    );
  }

  return Sale(
    id: 'SAMPLE-PREVIEW',
    invoiceNumber: 'INV-00123',
    date: DateTime(2026, 8, 29),
    customerName: 'Walk-In Customer',
    items: [
      line('Kids T-Shirt', 1000, 5, 25),
      line('Cotton Shirt', 2000, 12, 120),
      line('Mens Jeans', 1000, 18, 90),
    ],
    subtotal: 4000,
    taxAmount: 470,
    grandTotal: 4470,
    paymentMethod: 'UPI',
    taxableAmount: 4000,
    cgstAmount: 235,
    sgstAmount: 235,
    documentType: 'TAX INVOICE',
  );
}
