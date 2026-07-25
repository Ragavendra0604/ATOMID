import 'package:atomid/core/utils/image_provider_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:atomid/data/models/invoice_settings_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class InvoiceSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  ConsumerState<InvoiceSettingsScreen> createState() =>
      _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends ConsumerState<InvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _footerController;
  late TextEditingController _upiIdController;
  late TextEditingController _termsController;

  bool _showUpiQr = false;
  bool _showCompanyLogo = true;
  String _upiQrImagePath = '';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(invoiceSettingsProvider);

    _footerController = TextEditingController(text: settings.footerText);
    _upiIdController = TextEditingController(text: settings.upiId);
    _termsController = TextEditingController(text: settings.termsAndConditions);

    _showUpiQr = settings.showUpiQr;
    _showCompanyLogo = settings.showCompanyLogo;
    _upiQrImagePath = settings.upiQrImagePath;
  }

  @override
  void dispose() {
    _footerController.dispose();
    _upiIdController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _upiQrImagePath = pickedFile.path;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final newSettings = InvoiceSettingsModel(
      footerText: _footerController.text.trim(),
      showUpiQr: _showUpiQr,
      upiId: _upiIdController.text.trim(),
      upiQrImagePath: _upiQrImagePath,
      showCompanyLogo: _showCompanyLogo,
      termsAndConditions: _termsController.text.trim(),
    );

    await ref.read(storageRepositoryProvider).saveInvoiceSettings(newSettings);

    // Invalidate the provider to refresh
    ref.invalidate(invoiceSettingsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice settings saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Customization'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveSettings,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'General Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Show Company Logo'),
                subtitle: const Text('Display the company logo on invoices'),
                value: _showCompanyLogo,
                onChanged: (val) => setState(() => _showCompanyLogo = val),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _footerController,
                decoration: const InputDecoration(
                  labelText: 'Invoice Footer Text',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Thank you for your business!',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _termsController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Terms and Conditions',
                  border: OutlineInputBorder(),
                  hintText: 'Enter T&C to print at the bottom of the invoice',
                ),
              ),

              const SizedBox(height: 32),
              const Text(
                'UPI & QR Code Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Show UPI QR Code'),
                subtitle: const Text('Display QR code when payment is UPI'),
                value: _showUpiQr,
                onChanged: (val) => setState(() => _showUpiQr = val),
              ),
              if (_showUpiQr) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _upiIdController,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., yourname@upi',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('UPI QR Code Image'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_upiQrImagePath.isNotEmpty)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: getFileImageProvider(_upiQrImagePath),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: Text(
                        _upiQrImagePath.isEmpty
                            ? 'Select Image'
                            : 'Change Image',
                      ),
                    ),
                    if (_upiQrImagePath.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _upiQrImagePath = ''),
                        child: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upload a static QR code image to be printed on receipts. Leave blank if not required.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text(
                    'Save Settings',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
