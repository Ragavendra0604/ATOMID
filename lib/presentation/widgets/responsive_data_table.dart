import 'package:flutter/material.dart';
import 'package:atomid/core/utils/responsive.dart';

class ResponsiveDataTable<T> extends StatelessWidget {
  final List<String> headers;
  final List<T> items;
  final Widget Function(BuildContext context, T item) mobileCardBuilder;
  final DataRow Function(T item) dataRowBuilder;
  final Widget? emptyWidget;

  const ResponsiveDataTable({
    super.key,
    required this.headers,
    required this.items,
    required this.mobileCardBuilder,
    required this.dataRowBuilder,
    this.emptyWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && emptyWidget != null) {
      return emptyWidget!;
    }

    return ResponsiveBuilder(
      mobileBuilder: (context) => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            mobileCardBuilder(context, items[index]),
      ),
      tabletBuilder: (context) => _buildTable(context, isScrollable: true),
      desktopBuilder: (context) => _buildTable(context, isScrollable: false),
    );
  }

  Widget _buildTable(BuildContext context, {required bool isScrollable}) {
    final dataTable = DataTable(
      headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
      columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
      rows: items.map((item) => dataRowBuilder(item)).toList(),
      dataRowMaxHeight: double.infinity,
      dataRowMinHeight: 60,
    );

    if (isScrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: dataTable,
      );
    } else {
      return SizedBox(width: double.infinity, child: dataTable);
    }
  }
}
