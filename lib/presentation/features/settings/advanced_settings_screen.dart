import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/gst_rate_config_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  ConsumerState<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends ConsumerState<AdvancedSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _taxMode;
  late String _walkInPosPolicy;
  late String _inclusiveTaxRounding;
  late String _defaultUqc;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _taxMode = settings.taxMode;
    _walkInPosPolicy = settings.walkInPosPolicy;
    _inclusiveTaxRounding = settings.inclusiveTaxRounding;
    _defaultUqc = settings.defaultUqc;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final currentSettings = ref.read(settingsProvider);
    final newSettings = currentSettings.copyWith(
      taxMode: _taxMode,
      walkInPosPolicy: _walkInPosPolicy,
      inclusiveTaxRounding: _inclusiveTaxRounding,
      defaultUqc: _defaultUqc,
    );
    
    await ref.read(storageRepositoryProvider).saveSettings(newSettings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advanced Settings saved.')));
  }

  void _openGstRateManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => const _GstRateManagerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Admin Setup'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ResponsivePadding.getScreenPadding(context),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heading('GST & Pricing Engine (Admin Only)'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TaxModeSelector(
                              mode: _taxMode,
                              onChanged: (mode) => setState(() => _taxMode = mode),
                            ),
                            const Divider(height: 24),
                            DropdownButtonFormField<String>(
                              initialValue: _walkInPosPolicy,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Walk-In Customer Place of Supply Policy',
                                border: OutlineInputBorder(),
                                helperText: 'Determines how POS assigns place of supply for over-the-counter sales',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'USE_SHOP_STATE',
                                  child: Text('Default to Shop State (Intra-State POS)'),
                                ),
                                DropdownMenuItem(
                                  value: 'REQUIRE_STATE',
                                  child: Text('Mandatory State Selection for all customers'),
                                ),
                                DropdownMenuItem(
                                  value: 'ASK_AT_CHECKOUT',
                                  child: Text('Prompt State Selection at Checkout'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _walkInPosPolicy = v);
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _inclusiveTaxRounding,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tax-Inclusive Price Rounding',
                                border: OutlineInputBorder(),
                                helperText: 'Which figure wins when a tax-inclusive price cannot give both an exact total and an exact tax.',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'SHELF_PRICE',
                                  child: Text('Marked price is exact (tax is the remainder)'),
                                ),
                                DropdownMenuItem(
                                  value: 'TAX_RATE',
                                  child: Text('Tax matches the rate (total may differ by a paisa)'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _inclusiveTaxRounding = v);
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _defaultUqc,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Default UQC (Unit of Measure)',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'PCS', child: Text('PCS (Pieces)')),
                                DropdownMenuItem(value: 'NOS', child: Text('NOS (Numbers)')),
                                DropdownMenuItem(value: 'SET', child: Text('SET (Sets)')),
                                DropdownMenuItem(value: 'MTR', child: Text('MTR (Meters)')),
                                DropdownMenuItem(value: 'KGS', child: Text('KGS (Kilograms)')),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _defaultUqc = v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.tune_outlined),
                        title: const Text('Statutory GST Rate Presets'),
                        subtitle: const Text('Configure 0%, 5%, 12%, 18%, 28% and custom date-effective rates'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openGstRateManager,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _TaxModeSelector extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _TaxModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInclusive = mode == TaxMode.inclusive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tax Handling on Listed Selling Prices',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(TaxMode.inclusive),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isInclusive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: isInclusive ? 2 : 1,
              ),
              color: isInclusive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
            ),
            child: Row(
              children: [
                Icon(
                  isInclusive ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isInclusive ? theme.colorScheme.primary : theme.colorScheme.outline,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inclusive (MRP Contains GST)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isInclusive ? theme.colorScheme.primary : null,
                        ),
                      ),
                      Text(
                        'Tag price is final MRP. Tax is back-calculated.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(TaxMode.exclusive),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: !isInclusive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: !isInclusive ? 2 : 1,
              ),
              color: !isInclusive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
            ),
            child: Row(
              children: [
                Icon(
                  !isInclusive ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: !isInclusive ? theme.colorScheme.primary : theme.colorScheme.outline,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exclusive (GST Added on Top)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: !isInclusive ? theme.colorScheme.primary : null,
                        ),
                      ),
                      Text(
                        'Tag price is net taxable. Tax is added at checkout.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GstRateManagerSheet extends ConsumerStatefulWidget {
  const _GstRateManagerSheet();

  @override
  ConsumerState<_GstRateManagerSheet> createState() => _GstRateManagerSheetState();
}

class _GstRateManagerSheetState extends ConsumerState<_GstRateManagerSheet> {
  void _editRate([GstRateConfig? existing]) {
    final nameCtrl = TextEditingController(text: existing?.rateName ?? 'GST ');
    final rateCtrl = TextEditingController(text: existing != null ? Fmt.amount(existing.rate) : '5');
    final cessCtrl = TextEditingController(text: existing != null ? Fmt.amount(existing.cessRate) : '0');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add GST Rate Preset' : 'Edit GST Rate'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Rate Name (e.g. GST 5%)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'GST Rate %', suffixText: '%', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cessCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cess Rate % (Optional)', suffixText: '%', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description / Notes', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final rateVal = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
              final cessVal = double.tryParse(cessCtrl.text.trim()) ?? 0.0;
              final nameVal = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'GST ${Fmt.amount(rateVal)}%';
              final config = GstRateConfig(
                id: existing?.id ?? Ids.generate(),
                rateName: nameVal,
                rate: rateVal,
                cessRate: cessVal,
                effectiveFrom: existing?.effectiveFrom ?? DateTime(2017, 7, 1),
                description: descCtrl.text.trim(),
                updatedAt: DateTime.now(),
              );
              await ref.read(storageRepositoryProvider).saveGstRateConfig(config);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(storageRepositoryProvider);
    final rates = repo.getGstRateConfigs();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('GST Rate Configurations', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Statutory rates applicable on dresses and apparel under Indian GST.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: rates.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final r = rates[idx];
                return ListTile(
                  title: Text(r.rateName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('GST: ${Fmt.amount(r.rate)}%${r.cessRate > 0 ? " + Cess: ${Fmt.amount(r.cessRate)}%" : ""}${r.description.isNotEmpty ? " • ${r.description}" : ""}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: 'Edit GST rate', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editRate(r)),
                      IconButton(
                        tooltip: 'Delete GST rate',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          await repo.deleteGstRateConfig(r.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editRate(),
            icon: const Icon(Icons.add),
            label: const Text('Add Custom GST Rate Preset'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }
}
