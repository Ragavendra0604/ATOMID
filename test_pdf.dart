import 'dart:io';
import 'package:atomid/core/hardware/label_printer_profile.dart';
import 'package:atomid/core/hardware/label_layout_engine.dart';

void main() {
  final profile = LabelPrinterProfile.profile50x35TwoColumn;
  final engine = LabelLayoutEngine(profile);
  print('Labels per page: ${engine.labelsPerPage}');
  for (var qty in [2, 3, 4, 5, 10]) {
    print('Qty $qty -> Total Pages: ${engine.calculateTotalPages(qty)}');
  }
}
