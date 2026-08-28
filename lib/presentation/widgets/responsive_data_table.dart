import 'package:flutter/material.dart';
import 'package:atomid/core/utils/responsive.dart';

/// A list on narrow screens and a table on wide ones.
///
/// Both forms scroll on their own. They used to be laid out as if a parent
/// were doing the scrolling — `shrinkWrap` with
/// [NeverScrollableScrollPhysics] on the list, and an unscrolled column of
/// rows in the table — but every caller drops this straight into a
/// `Scaffold.body`, so a list longer than the screen simply could not be
/// reached, and a phone turned to landscape overflowed the bottom edge.
class ResponsiveDataTable<T> extends StatelessWidget {
  final List<String> headers;
  final List<T> items;
  final Widget Function(BuildContext context, T item) mobileCardBuilder;
  final DataRow Function(T item) dataRowBuilder;
  final Widget? emptyWidget;

  /// Set when the table really is inside another scrollable, in which case it
  /// sizes to its content and leaves scrolling to the parent.
  final bool nested;

  const ResponsiveDataTable({
    super.key,
    required this.headers,
    required this.items,
    required this.mobileCardBuilder,
    required this.dataRowBuilder,
    this.emptyWidget,
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && emptyWidget != null) {
      return emptyWidget!;
    }

    return ResponsiveBuilder(
      mobileBuilder: (context) => ListView.builder(
        shrinkWrap: nested,
        physics: nested ? const NeverScrollableScrollPhysics() : null,
        // Clears the bottom system inset and any floating action button, so
        // the last card is not stuck under them.
        padding: EdgeInsets.only(
          top: 8,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            mobileCardBuilder(context, items[index]),
      ),
      tabletBuilder: (context) => _buildTable(context),
      desktopBuilder: (context) => _buildTable(context),
    );
  }

  Widget _buildTable(BuildContext context) {
    final dataTable = DataTable(
      headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
      columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
      rows: items.map((item) => dataRowBuilder(item)).toList(),
      dataRowMaxHeight: double.infinity,
      dataRowMinHeight: 60,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Horizontal inside vertical: a wide table scrolls sideways while the
        // rows still scroll down, which is what a phone held in landscape
        // needs. The minimum width keeps a narrow table filling the pane
        // instead of huddling on the left.
        final table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: dataTable,
          ),
        );

        if (nested) return table;

        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.of(context).padding.bottom,
          ),
          child: table,
        );
      },
    );
  }
}
