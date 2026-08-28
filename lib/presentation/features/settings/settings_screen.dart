import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/gst_rate_config_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/presentation/features/auth/auth_screen.dart';
import 'package:atomid/presentation/features/settings/backup_screen.dart';
import 'package:atomid/presentation/features/settings/company_profile_screen.dart';
import 'package:atomid/presentation/features/settings/invoice_settings_screen.dart';
import 'package:atomid/presentation/features/settings/loyalty_settings_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeName;
  late final TextEditingController _currency;
  late String _pdfPageSize;
  late String _taxMode;
  late bool _roundOffEnabled;
  late bool _hsnRequired;
  late String _walkInPosPolicy;
  late String _inclusiveTaxRounding;
  late bool _showGstBreakdown;
  late bool _showHsnSummary;
  late String _defaultUqc;
  late String _thermalReceiptSize;
  late bool _showTaxOnThermalReceipt;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _storeName = TextEditingController(text: settings.companyName);
    _currency = TextEditingController(text: settings.currencySymbol);
    _pdfPageSize = settings.pdfPageSize;
    _taxMode = settings.taxMode;
    _roundOffEnabled = settings.roundOffEnabled;
    _hsnRequired = settings.hsnRequired;
    _walkInPosPolicy = settings.walkInPosPolicy;
    _inclusiveTaxRounding = settings.inclusiveTaxRounding;
    _showGstBreakdown = settings.showGstBreakdown;
    _showHsnSummary = settings.showHsnSummary;
    _defaultUqc = settings.defaultUqc;
    _thermalReceiptSize = settings.thermalReceiptSize;
    _showTaxOnThermalReceipt = settings.showTaxOnThermalReceipt;
  }

  @override
  void dispose() {
    _storeName.dispose();
    _currency.dispose();
    super.dispose();
  }

  SettingsModel _draft({bool? isDarkMode}) {
    return ref
        .read(settingsProvider)
        .copyWith(
          isDarkMode: isDarkMode,
          companyName: _storeName.text.trim(),
          currencySymbol: _currency.text.trim(),
          pdfPageSize: _pdfPageSize,
          taxMode: _taxMode,
          roundOffEnabled: _roundOffEnabled,
          hsnRequired: _hsnRequired,
          walkInPosPolicy: _walkInPosPolicy,
          inclusiveTaxRounding: _inclusiveTaxRounding,
          showGstBreakdown: _showGstBreakdown,
          showHsnSummary: _showHsnSummary,
          defaultUqc: _defaultUqc,
          thermalReceiptSize: _thermalReceiptSize,
          showTaxOnThermalReceipt: _showTaxOnThermalReceipt,
        );
  }

  Future<void> _save({bool showToast = true}) async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(storageRepositoryProvider).saveSettings(_draft());

    if (!mounted || !showToast) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
  }

  Future<void> _setDarkMode(bool value) async {
    await ref
        .read(storageRepositoryProvider)
        .saveSettings(_draft(isDarkMode: value));
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
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                    _heading('Store Information'),
                    TextFormField(
                      controller: _storeName,
                      decoration: const InputDecoration(
                        labelText: 'Store name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Store name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Currency symbol',
                        hintText: '₹, \$, £, €',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 3,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Currency symbol is required'
                          : null,
                    ),

                    _heading('GST & Pricing Engine'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TaxModeSelector(
                              mode: _taxMode,
                              onChanged: (mode) =>
                                  setState(() => _taxMode = mode),
                            ),
                            const Divider(height: 24),
                            // The shop-wide "default tax rate" box used to sit
                            // here. It no longer reaches a bill — a product's
                            // GST comes from the product — so leaving an
                            // editable percentage on this screen only invited
                            // someone to set it and expect it to apply. The
                            // stored value is left untouched for older records
                            // and for sync.
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _roundOffEnabled,
                              onChanged: (val) =>
                                  setState(() => _roundOffEnabled = val),
                              title: const Text('Automatic Invoice Round-Off'),
                              subtitle: const Text(
                                'Rounds final payable bill amount to nearest integer (e.g. ₹599.40 → ₹599.00, ₹599.60 → ₹600.00).',
                              ),
                            ),
                            const Divider(height: 24),
                            DropdownButtonFormField<String>(
                              initialValue: _walkInPosPolicy,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText:
                                    'Walk-In Customer Place of Supply Policy',
                                border: OutlineInputBorder(),
                                helperText:
                                    'Determines how POS assigns place of supply for over-the-counter sales',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'USE_SHOP_STATE',
                                  child: Text(
                                    'Default to Shop State (Intra-State POS)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'REQUIRE_STATE',
                                  child: Text(
                                    'Mandatory State Selection for all customers',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'ASK_AT_CHECKOUT',
                                  child: Text(
                                    'Prompt State Selection at Checkout',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _walkInPosPolicy = v);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _inclusiveTaxRounding,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tax-Inclusive Price Rounding',
                                border: OutlineInputBorder(),
                                helperText:
                                    'Which figure wins when a tax-inclusive price cannot give both an exact total and an exact tax. Ask your accountant.',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'SHELF_PRICE',
                                  child: Text(
                                    'Marked price is exact (tax is the remainder)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'TAX_RATE',
                                  child: Text(
                                    'Tax matches the rate (total may differ by a paisa)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _inclusiveTaxRounding = v);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _defaultUqc,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Default UQC (Unit of Measure)',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'PCS',
                                        child: Text(
                                          'PCS (Pieces)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'NOS',
                                        child: Text(
                                          'NOS (Numbers)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'SET',
                                        child: Text(
                                          'SET (Sets)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'MTR',
                                        child: Text(
                                          'MTR (Meters)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'KGS',
                                        child: Text(
                                          'KGS (Kilograms)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _defaultUqc = v);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _hsnRequired,
                              onChanged: (val) =>
                                  setState(() => _hsnRequired = val),
                              title: const Text(
                                'Mandatory HSN on Product Entry',
                              ),
                              subtitle: const Text(
                                'Blocks saving products without a valid HSN code.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    _link(
                      icon: Icons.tune_outlined,
                      title: 'Statutory GST Rate Presets',
                      subtitle:
                          'Configure 0%, 5%, 12%, 18%, 28% and custom date-effective rates',
                      onTap: _openGstRateManager,
                    ),

                    _heading('Receipt & Invoice Display'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showGstBreakdown,
                              onChanged: (val) =>
                                  setState(() => _showGstBreakdown = val),
                              title: const Text('Print Tax Breakdown Table'),
                              subtitle: const Text(
                                'Prints CGST, SGST, UTGST, and IGST breakdowns on A4 Invoices.',
                              ),
                            ),
                            const Divider(height: 24),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showHsnSummary,
                              onChanged: (val) =>
                                  setState(() => _showHsnSummary = val),
                              title: const Text('Print HSN Summary Table'),
                              subtitle: const Text(
                                'Prints statutory HSN-wise tax summary table at bottom of A4 Invoice.',
                              ),
                            ),
                            const Divider(height: 24),
                            DropdownButtonFormField<String>(
                              initialValue: _thermalReceiptSize,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Thermal POS Printer Paper Width',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: '80mm',
                                  child: Text(
                                    '80mm (Standard POS Thermal Receipt)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: '58mm',
                                  child: Text(
                                    '58mm (Compact Mobile Thermal Receipt)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _thermalReceiptSize = v);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showTaxOnThermalReceipt,
                              onChanged: (val) => setState(
                                () => _showTaxOnThermalReceipt = val,
                              ),
                              title: const Text(
                                'Show Tax Summary on Thermal Receipt',
                              ),
                              subtitle: const Text(
                                'Prints compact GST & Taxable breakdown on thermal slips.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    _heading('Appearance & Formats'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: settings.isDarkMode,
                            onChanged: _setDarkMode,
                            title: const Text('Dark mode'),
                            secondary: Icon(
                              settings.isDarkMode
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DropdownButtonFormField<String>(
                          initialValue: _pdfPageSize,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'PDF Document Page Size',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'A4',
                              child: Text(
                                'A4',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Letter',
                              child: Text(
                                'Letter',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _pdfPageSize = v);
                          },
                        ),
                      ),
                    ),

                    _heading('Configure Modules'),
                    _link(
                      icon: Icons.business_outlined,
                      title: 'Business Details & Shop State',
                      subtitle:
                          'Legal name, shop GSTIN, state code, address and logo',
                      onTap: () => _open(const CompanyProfileScreen()),
                    ),
                    _link(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoice Layout & UPI QR',
                      subtitle:
                          'Footer text, payment terms and instant UPI QR code',
                      onTap: () => _open(const InvoiceSettingsScreen()),
                    ),
                    _link(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Customer Reward Points',
                      subtitle:
                          ref.watch(loyaltySettingsProvider).isLoyaltyEnabled
                          ? 'On — earning and redemption rules'
                          : 'Off — customers are not earning points',
                      onTap: () => _open(const LoyaltySettingsScreen()),
                    ),
                    _link(
                      icon: ref.watch(isSignedInProvider)
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      title: ref.watch(isSignedInProvider)
                          ? 'Cloud backup is on'
                          : 'Back up to the cloud',
                      subtitle:
                          ref.watch(authServiceProvider).currentUser?.email ??
                          'Sign in to sync this device when it is online',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      ),
                    ),
                    if (ref.watch(isSignedInProvider))
                      _link(
                        icon: Icons.logout,
                        title: 'Sign out',
                        subtitle:
                            'Stops syncing. Everything stays on this device.',
                        onTap: _signOut,
                      ),
                    _link(
                      icon: Icons.save_alt_outlined,
                      title: 'Backup and restore',
                      subtitle: 'Save a copy of everything, or put one back',
                      onTap: () => _open(const BackupScreen()),
                    ),

                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save settings'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _AboutFooter(),
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Syncing will pause. Your products, sales and settings will stay on '
          'this device, and you can sign back in at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay signed in'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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

  Widget _link({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
                color: isInclusive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isInclusive ? 2 : 1,
              ),
              color: isInclusive
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isInclusive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isInclusive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
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
                color: !isInclusive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: !isInclusive ? 2 : 1,
              ),
              color: !isInclusive
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  !isInclusive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: !isInclusive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
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
                          color: !isInclusive
                              ? theme.colorScheme.primary
                              : null,
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
  ConsumerState<_GstRateManagerSheet> createState() =>
      _GstRateManagerSheetState();
}

class _GstRateManagerSheetState extends ConsumerState<_GstRateManagerSheet> {
  void _editRate([GstRateConfig? existing]) {
    final nameCtrl = TextEditingController(text: existing?.rateName ?? 'GST ');
    final rateCtrl = TextEditingController(
      text: existing != null ? Fmt.amount(existing.rate) : '5',
    );
    final cessCtrl = TextEditingController(
      text: existing != null ? Fmt.amount(existing.cessRate) : '0',
    );
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
                decoration: const InputDecoration(
                  labelText: 'Rate Name (e.g. GST 5%)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'GST Rate %',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cessCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cess Rate % (Optional)',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description / Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final rateVal = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
              final cessVal = double.tryParse(cessCtrl.text.trim()) ?? 0.0;
              final nameVal = nameCtrl.text.trim().isNotEmpty
                  ? nameCtrl.text.trim()
                  : 'GST ${Fmt.amount(rateVal)}%';

              final config = GstRateConfig(
                id: existing?.id ?? Ids.generate(),
                rateName: nameVal,
                rate: rateVal,
                cessRate: cessVal,
                effectiveFrom: existing?.effectiveFrom ?? DateTime(2017, 7, 1),
                description: descCtrl.text.trim(),
                updatedAt: DateTime.now(),
              );

              await ref
                  .read(storageRepositoryProvider)
                  .saveGstRateConfig(config);
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
              Expanded(
                child: Text(
                  'GST Rate Configurations',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Statutory rates applicable on dresses and apparel under Indian GST.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: rates.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final r = rates[idx];
                return ListTile(
                  title: Text(
                    r.rateName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'GST: ${Fmt.amount(r.rate)}%${r.cessRate > 0 ? " + Cess: ${Fmt.amount(r.cessRate)}%" : ""}'
                    '${r.description.isNotEmpty ? " • ${r.description}" : ""}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit GST rate',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _editRate(r),
                      ),
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
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'AtomID Store POS • Single Retail Shop Edition',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
