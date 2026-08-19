import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;

  const CustomerFormScreen({super.key, this.customer});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _mobileController;
  late TextEditingController _gstController;
  late TextEditingController _addressController;
  late TextEditingController _creditLimitController;
  late TextEditingController _creditDaysController;
  late TextEditingController _openingBalanceController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;
  late TextEditingController _tagController;

  String _status = 'Active';
  String _customerGroup = 'General';
  List<String> _tags = [];
  List<String> _attachments = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _mobileController = TextEditingController(
      text: widget.customer?.mobile ?? '',
    );
    _gstController = TextEditingController(
      text: widget.customer?.gstNumber ?? '',
    );
    _addressController = TextEditingController(
      text: widget.customer?.address ?? '',
    );
    _creditLimitController = TextEditingController(
      text: widget.customer?.creditLimit.toString() ?? '0',
    );
    _creditDaysController = TextEditingController(
      text: widget.customer?.creditDays.toString() ?? '0',
    );
    _openingBalanceController = TextEditingController(
      text: widget.customer?.openingBalance.toString() ?? '0',
    );
    _emailController = TextEditingController(
      text: widget.customer?.email ?? '',
    );
    _notesController = TextEditingController(
      text: widget.customer?.notes ?? '',
    );
    _tagController = TextEditingController();

    _status = widget.customer?.status ?? 'Active';
    _customerGroup = widget.customer?.customerGroup ?? 'General';
    _tags = widget.customer?.tags.toList() ?? [];
    _attachments = widget.customer?.attachments.toList() ?? [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _gstController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    _creditDaysController.dispose();
    _openingBalanceController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    final service = ref.read(customerServiceProvider);
    final repo = ref.read(storageRepositoryProvider);
    final now = DateTime.now();

    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim();

    if (service.isDuplicate(mobile, email, excludeId: widget.customer?.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer with this mobile or email already exists!'),
        ),
      );
      return;
    }

    final isNew = widget.customer == null;
    final id = isNew ? const Uuid().v4() : widget.customer!.id;
    final code = isNew
        ? 'CUST-${now.millisecondsSinceEpoch.toString().substring(5)}'
        : widget.customer!.code;

    final customer = Customer(
      id: id,
      code: code,
      name: _nameController.text.trim(),
      mobile: _mobileController.text.trim(),
      gstNumber: _gstController.text.trim(),
      address: _addressController.text.trim(),
      creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
      creditDays: int.tryParse(_creditDaysController.text) ?? 0,
      openingBalance: double.tryParse(_openingBalanceController.text) ?? 0,
      currentBalance: isNew
          ? (double.tryParse(_openingBalanceController.text) ?? 0)
          : widget.customer!.currentBalance,
      status: _status,
      createdDate: isNew ? now : widget.customer!.createdDate,
      email: email,
      customerGroup: _customerGroup,
      notes: _notesController.text.trim(),
      tags: _tags,
      attachments: _attachments,
    );

    await service.saveCustomer(customer);

    // If new and has opening balance, record ledger entry
    if (isNew && customer.openingBalance != 0) {
      await repo.addLedgerEntry(
        customerId: customer.id,
        date: now,
        transactionType: 'Opening Balance',
        referenceId: 'OPENING',
        debit: customer.openingBalance > 0 ? customer.openingBalance : 0,
        credit: customer.openingBalance < 0 ? customer.openingBalance.abs() : 0,
        notes: 'Initial opening balance',
      );
    } else {
      ref.invalidate(customersProvider);
      ref.invalidate(filteredCustomersProvider);
    }

    if (mounted) {
      Navigator.pop(context, customer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer == null ? 'Add Customer' : 'Edit Customer'),
        actions: [
          IconButton(
            tooltip: 'Save customer',
            icon: const Icon(Icons.check),
            onPressed: _saveCustomer,
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
                'Basic Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name*',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number*',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? 'Mobile is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gstController,
                decoration: const InputDecoration(
                  labelText: 'GST Number (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Billing Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address (Optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _customerGroup,
                decoration: const InputDecoration(
                  labelText: 'Customer Group',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'General', child: Text('General')),
                  DropdownMenuItem(value: 'VIP', child: Text('VIP')),
                  DropdownMenuItem(
                    value: 'Wholesale',
                    child: Text('Wholesale'),
                  ),
                ],
                onChanged: (v) => setState(() => _customerGroup = v!),
              ),

              const SizedBox(height: 32),
              const Text(
                'Tags & Notes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tagController,
                decoration: InputDecoration(
                  labelText: 'Add Tag',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Add tag',
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final tag = _tagController.text.trim();
                      if (tag.isNotEmpty && !_tags.contains(tag)) {
                        setState(() => _tags.add(tag));
                        _tagController.clear();
                      }
                    },
                  ),
                ),
                onFieldSubmitted: (v) {
                  final tag = v.trim();
                  if (tag.isNotEmpty && !_tags.contains(tag)) {
                    setState(() => _tags.add(tag));
                    _tagController.clear();
                  }
                },
              ),
              if (_tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 8,
                    children: _tags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            onDeleted: () {
                              setState(() => _tags.remove(tag));
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Internal Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32),
              const Text(
                'Financial Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _creditLimitController,
                      decoration: const InputDecoration(
                        labelText: 'Credit Limit',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _creditDaysController,
                      decoration: const InputDecoration(
                        labelText: 'Credit Days',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.customer == null)
                TextFormField(
                  controller: _openingBalanceController,
                  decoration: const InputDecoration(
                    labelText:
                        'Opening Balance (+ for Debit/Due, - for Credit/Advance)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),

              const SizedBox(height: 32),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveCustomer,
                  child: const Text(
                    'Save Customer',
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
