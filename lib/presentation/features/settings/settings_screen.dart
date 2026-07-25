import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/features/settings/invoice_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _companyNameCtrl;
  late TextEditingController _currencyCtrl;
  String _selectedPdfSize = 'A4';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _companyNameCtrl = TextEditingController(text: settings.companyName);
    _currencyCtrl = TextEditingController(text: settings.currencySymbol);
    _selectedPdfSize = settings.pdfPageSize;
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final repo = ref.read(storageRepositoryProvider);
      final currentSettings = ref.read(settingsProvider);

      final newSettings = SettingsModel(
        isDarkMode: currentSettings.isDarkMode,
        companyName: _companyNameCtrl.text.trim(),
        currencySymbol: _currencyCtrl.text.trim(),
        pdfPageSize: _selectedPdfSize,
      );

      await repo.saveSettings(newSettings);
      ref.invalidate(settingsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ResponsiveBuilder(
        mobileBuilder: (context) => _buildMobileForm(settings),
        desktopBuilder: (context) => _buildDesktopForm(settings),
      ),
    );
  }

  Widget _buildMobileForm(SettingsModel settings) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: ResponsivePadding.getScreenPadding(context),
        children: _buildFormChildren(settings),
      ),
    );
  }

  Widget _buildDesktopForm(SettingsModel settings) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left category rail
        SizedBox(
          width: 250,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('General'),
                selected: true,
                onTap: () {},
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withAlpha(30),
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Printing (Coming Soon)'),
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right form area
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: ResponsivePadding.getScreenPadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ResponsiveBreakpoints.maxFormWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildFormChildren(settings),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFormChildren(SettingsModel settings) {
    return [
      const Text(
        'Store Details',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _companyNameCtrl,
        decoration: const InputDecoration(
          labelText: 'Company/Store Name',
          prefixIcon: Icon(Icons.store),
          border: OutlineInputBorder(),
        ),
        validator: (val) => val == null || val.trim().isEmpty
            ? 'Company name is required'
            : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _currencyCtrl,
        decoration: const InputDecoration(
          labelText: 'Currency Symbol (e.g. \$, ₹)',
          prefixIcon: Icon(Icons.attach_money),
          border: OutlineInputBorder(),
        ),
        validator: (val) => val == null || val.trim().isEmpty
            ? 'Currency symbol is required'
            : null,
      ),
      const SizedBox(height: 32),
      const Text(
        'App Preferences',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      Card(
        child: SwitchListTile(
          title: const Text('Dark Mode'),
          secondary: Icon(
            settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
          ),
          value: settings.isDarkMode,
          onChanged: (val) async {
            final repo = ref.read(storageRepositoryProvider);
            final newSettings = SettingsModel(
              isDarkMode: val,
              companyName: _companyNameCtrl.text.trim(),
              currencySymbol: _currencyCtrl.text.trim(),
              pdfPageSize: _selectedPdfSize,
            );
            await repo.saveSettings(newSettings);
            ref.invalidate(settingsProvider);
          },
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedPdfSize,
            decoration: const InputDecoration(
              labelText: 'PDF Export Page Size',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'A4', child: Text('A4 (Standard)')),
              DropdownMenuItem(value: 'Letter', child: Text('Letter')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedPdfSize = val);
              }
            },
          ),
        ),
      ),
      const SizedBox(height: 32),
      const Text(
        'Billing & Invoices',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long),
          title: const Text('Invoice Customization'),
          subtitle: const Text('Configure footer text, UPI QR, and logos'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen()),
            );
          },
        ),
      ),
      const SizedBox(height: 32),
      SizedBox(
        height: 50,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save),
          label: const Text('Save Settings'),
        ),
      ),
    ];
  }
}
