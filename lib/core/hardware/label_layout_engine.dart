
import 'package:pdf/pdf.dart';
import 'label_printer_profile.dart';

class LabelLayoutEngine {
  final LabelPrinterProfile profile;

  LabelLayoutEngine(this.profile) {
    _validate();
  }

  void _validate() {
    if (profile.labelWidthMm < 20 || profile.labelHeightMm < 15) {
      throw Exception(
        'Label dimensions (${profile.labelWidthMm}x${profile.labelHeightMm} mm) are too small. Minimum required is 20x15 mm to safely render a barcode.',
      );
    }
    if (profile.mediaWidthMm <= 0 || profile.mediaHeightMm <= 0) {
      throw Exception('Media dimensions must be strictly positive.');
    }
    if (profile.columns < 1) {
      throw Exception('Number of columns must be at least 1.');
    }

    final requiredWidth = profile.leftMarginMm +
        (profile.columns * profile.labelWidthMm) +
        ((profile.columns - 1) * profile.horizontalGapMm) +
        profile.rightMarginMm;

    if (requiredWidth > profile.mediaWidthMm) {
      throw Exception(
        'Configured label layout width ($requiredWidth mm) exceeds physical media width (${profile.mediaWidthMm} mm).',
      );
    }
  }

  PdfPageFormat get pdfPageFormat {
    if (profile.pageModel == LabelPageModel.singleLabel) {
      return PdfPageFormat(
        profile.labelWidthMm * PdfPageFormat.mm,
        profile.labelHeightMm * PdfPageFormat.mm,
        marginAll: 0,
      );
    } else {
      return PdfPageFormat(
        profile.mediaWidthMm * PdfPageFormat.mm,
        profile.mediaHeightMm * PdfPageFormat.mm,
        marginAll: 0,
      );
    }
  }

  int get labelsPerPage {
    if (profile.pageModel == LabelPageModel.singleLabel) {
      return 1;
    } else {
      return profile.columns;
    }
  }

  int calculateTotalPages(int totalLabels) {
    if (totalLabels <= 0) return 0;
    final perPage = labelsPerPage;
    return (totalLabels / perPage).ceil();
  }

  double getColumnOffset(int columnIndex) {
    if (columnIndex < 0 || columnIndex >= profile.columns) return 0;
    return profile.leftMarginMm + (profile.labelWidthMm + profile.horizontalGapMm) * columnIndex;
  }
}
