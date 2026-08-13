import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:uuid/uuid.dart';
import 'package:atomid/core/utils/responsive.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final Supplier? existingSupplier;

  const SupplierFormScreen({super.key, this.existingSupplier});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _contactPersonCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _openingBalanceCtrl;

  String _supplierCategory = 'General';
  String _paymentTerms = 'Net 30';
  double _rating = 0.0;

  @override
  void initState() {
    super.initState();
    final s = widget.existingSupplier;
    _nameCtrl = TextEditingController(text: s?.supplierName ?? '');
    _codeCtrl = TextEditingController(text: s?.supplierCode ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _emailCtrl = TextEditingController(text: s?.email ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _gstCtrl = TextEditingController(text: s?.gstNumber ?? '');
    _contactPersonCtrl = TextEditingController(text: s?.contactPerson ?? '');
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
    _openingBalanceCtrl = TextEditingController(text: '0');

    _supplierCategory = s?.supplierCategory ?? 'General';
    _paymentTerms = s?.paymentTerms ?? 'Net 30';
    _rating = s?.rating ?? 0.0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _gstCtrl.dispose();
    _contactPersonCtrl.dispose();
    _notesCtrl.dispose();
    _openingBalanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form')),
      );
      return;
    }

    final isNew = widget.existingSupplier == null;
    final id = widget.existingSupplier?.id ?? const Uuid().v4();
    final service = ref.read(supplierServiceProvider);
    final openingBalance = double.tryParse(_openingBalanceCtrl.text) ?? 0.0;
    final code = _codeCtrl.text.trim();

    if (service.isDuplicate(code, excludeId: widget.existingSupplier?.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier code already exists')),
      );
      return;
    }

    final supplier = Supplier(
      id: id,
      supplierCode: _codeCtrl.text.trim(),
      supplierName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      gstNumber: _gstCtrl.text.trim(),
      contactPerson: _contactPersonCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      createdDate: widget.existingSupplier?.createdDate ?? DateTime.now(),
      updatedDate: DateTime.now(),
      isActive: widget.existingSupplier?.isActive ?? true,
      supplierCategory: _supplierCategory,
      paymentTerms: _paymentTerms,
      rating: _rating,
      currentBalance: isNew
          ? openingBalance
          : widget.existingSupplier!.currentBalance,
    );

    await service.saveSupplier(
      supplier,
      isNew: isNew,
      openingBalance: openingBalance,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Supplier ${isNew ? 'created' : 'updated'} successfully',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingSupplier != null ? 'Edit Supplier' : 'Add Supplier',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Supplier',
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
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
                children: [
                  // Basic Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Basic Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Name *',
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Supplier name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Code *',
                              prefixIcon: Icon(Icons.tag),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Supplier code is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _supplierCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.category),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'General',
                                child: Text('General'),
                              ),
                              DropdownMenuItem(
                                value: 'Electronics',
                                child: Text('Electronics'),
                              ),
                              DropdownMenuItem(
                                value: 'Hardware',
                                child: Text('Hardware'),
                              ),
                              DropdownMenuItem(
                                value: 'Services',
                                child: Text('Services'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _supplierCategory = v!),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contact Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Contact Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contactPersonCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Contact Person',
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone',
                                    prefixIcon: Icon(Icons.phone),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _addressCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              prefixIcon: Icon(Icons.location_on),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Business Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Business Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _gstCtrl,
                            decoration: const InputDecoration(
                              labelText: 'GST Number',
                              prefixIcon: Icon(Icons.receipt_long),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _notesCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              prefixIcon: Icon(Icons.notes),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _paymentTerms,
                            decoration: const InputDecoration(
                              labelText: 'Payment Terms',
                              prefixIcon: Icon(Icons.payment),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Advance',
                                child: Text('Advance'),
                              ),
                              DropdownMenuItem(
                                value: 'Due on Receipt',
                                child: Text('Due on Receipt'),
                              ),
                              DropdownMenuItem(
                                value: 'Net 15',
                                child: Text('Net 15'),
                              ),
                              DropdownMenuItem(
                                value: 'Net 30',
                                child: Text('Net 30'),
                              ),
                              DropdownMenuItem(
                                value: 'Net 60',
                                child: Text('Net 60'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _paymentTerms = v!),
                          ),
                          if (widget.existingSupplier == null) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _openingBalanceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Opening Balance (Owed to Supplier)',
                                prefixIcon: Icon(Icons.account_balance_wallet),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.grey),
                              const SizedBox(width: 12),
                              const Text(
                                'Rating',
                                style: TextStyle(fontSize: 16),
                              ),
                              const Spacer(),
                              Slider(
                                value: _rating,
                                min: 0,
                                max: 5,
                                divisions: 10,
                                label: _rating.toStringAsFixed(1),
                                onChanged: (v) => setState(() => _rating = v),
                              ),
                              Text(_rating.toStringAsFixed(1)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ), // ConstrainedBox
          ), // Center
        ), // SingleChildScrollView
      ), // Form
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        label: const Text('Save Supplier'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
