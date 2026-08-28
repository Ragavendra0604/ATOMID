import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/widgets/responsive_data_table.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Scanned',
    'Generated',
    'Shared',
    'Printed',
    'Created',
    'Updated',
    'Deleted',
  ];

  @override
  Widget build(BuildContext context) {
    final historyList = ref.watch(historyListProvider);

    final filteredList = historyList.where((h) {
      bool matchesSearch =
          h.barcode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          h.productName.toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchesFilter =
          _selectedFilter == 'All' || h.action.contains(_selectedFilter);
      return matchesSearch && matchesFilter;
    }).toList();

    filteredList.sort((a, b) => b.date.compareTo(a.date));

    return ResponsiveBuilder(
      mobileBuilder: (context) => _buildMobileLayout(context, filteredList),
      tabletBuilder: (context) => _buildMobileLayout(context, filteredList),
      desktopBuilder: (context) => _buildDesktopLayout(context, filteredList),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    List<ActionHistory> filteredList,
  ) {
    // Search and filters live in the body rather than in `AppBar.bottom`.
    // That slot needs a height declared up front, and the 120 points it was
    // given were less than the field and the chip row actually take once the
    // text scale or a landscape toolbar changes — which is where the overflow
    // stripes in landscape came from.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Action History'),
        actions: [_buildClearButton()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchAndFilters(isDesktop: false),
            const Divider(height: 1),
            Expanded(child: _buildDataTable(filteredList)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<ActionHistory> filteredList,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Action History'),
        actions: [_buildClearButton()],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 300,
            // The filter column is taller than a short window, so it scrolls
            // rather than overflowing.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildSearchAndFilters(isDesktop: true),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildDataTable(filteredList),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearButton() {
    return IconButton(
      tooltip: 'Clear history',
      icon: const Icon(Icons.delete_sweep),
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AdaptiveDialog(
            title: const Text('Clear History'),
            content: const Text('Are you sure you want to delete all history?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final repo = ref.read(storageRepositoryProvider);
          await repo.clearHistory();
          ref.invalidate(historyListProvider);
        }
      },
    );
  }

  Widget _buildSearchAndFilters({required bool isDesktop}) {
    final searchField = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 0 : 16.0,
        vertical: 8.0,
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search barcode or product...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) => setState(() => _searchQuery = val),
      ),
    );

    final filtersWidget = isDesktop
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _filters.map((f) {
              final isSelected = _selectedFilter == f;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: FilterChip(
                  label: Text(f),
                  selected: isSelected,
                  onSelected: (val) => setState(() => _selectedFilter = f),
                ),
              );
            }).toList(),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: _filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(f),
                    selected: isSelected,
                    onSelected: (val) => setState(() => _selectedFilter = f),
                  ),
                );
              }).toList(),
            ),
          );

    return isDesktop
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchField,
              const SizedBox(height: 16),
              const Text(
                'Filters',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              filtersWidget,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [searchField, filtersWidget],
          );
  }

  Widget _buildDataTable(List<ActionHistory> list) {
    return ResponsiveDataTable<ActionHistory>(
      headers: const ['Action', 'Product', 'Barcode', 'Date'],
      items: list,
      emptyWidget: const Center(child: Text('No history found.')),
      mobileCardBuilder: (context, h) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                _getIconForAction(h.action),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              h.action,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${h.productName}\nBarcode: ${h.barcode}'),
            isThreeLine: true,
            trailing: Text(
              '${h.date.year}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')}\n${h.date.hour.toString().padLeft(2, '0')}:${h.date.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      },
      dataRowBuilder: (h) {
        return DataRow(
          cells: [
            DataCell(
              Row(
                children: [
                  Icon(
                    _getIconForAction(h.action),
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    h.action,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            DataCell(Text(h.productName)),
            DataCell(Text(h.barcode)),
            DataCell(
              Text(
                '${h.date.year}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')} ${h.date.hour.toString().padLeft(2, '0')}:${h.date.minute.toString().padLeft(2, '0')}',
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getIconForAction(String action) {
    if (action.contains('Scanned')) return Icons.qr_code_scanner;
    if (action.contains('Generated')) return Icons.picture_as_pdf;
    if (action.contains('Shared')) return Icons.share;
    if (action.contains('Printed')) return Icons.print;
    if (action.contains('Created')) return Icons.add_circle;
    if (action.contains('Updated')) return Icons.edit;
    if (action.contains('Deleted')) return Icons.delete;
    return Icons.history;
  }
}
