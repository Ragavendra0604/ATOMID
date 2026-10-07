enum LabelPageModel {
  singleLabel,
  multiColumnMedia,

  /// Continuous roll media — page height is calculated dynamically from the
  /// number of labels requested. Used by printers like TVS LP 46 DLITE.
  continuousRoll,
}

class LabelPrinterProfile {
  final String id;
  final String name;
  final double mediaWidthMm;
  final double mediaHeightMm;
  final double labelWidthMm;
  final double labelHeightMm;
  final int columns;
  final double horizontalGapMm;
  final double verticalGapMm;
  final double leftMarginMm;
  final double rightMarginMm;
  final double topMarginMm;
  final double bottomMarginMm;
  final LabelPageModel pageModel;

  const LabelPrinterProfile({
    required this.id,
    required this.name,
    required this.mediaWidthMm,
    required this.mediaHeightMm,
    required this.labelWidthMm,
    required this.labelHeightMm,
    required this.columns,
    this.horizontalGapMm = 0.0,
    this.verticalGapMm = 0.0,
    this.leftMarginMm = 0.0,
    this.rightMarginMm = 0.0,
    this.topMarginMm = 0.0,
    this.bottomMarginMm = 0.0,
    required this.pageModel,
  });

  /// The standard 50x35mm profile, assuming the driver is set up to receive a single 50x35 logical page
  /// and the hardware gap sensor distributes them natively across the columns.
  static const profile50x35Single = LabelPrinterProfile(
    id: '50x35',
    name: '50x35 mm',
    mediaWidthMm: 50.0,
    mediaHeightMm: 35.0,
    labelWidthMm: 50.0,
    labelHeightMm: 35.0,
    columns: 1,
    horizontalGapMm: 0.0,
    pageModel: LabelPageModel.singleLabel,
  );

  /// A 2-up profile for 50x35mm, assuming the driver is configured for a full ~102mm width
  /// and expects the application to supply two logical labels side-by-side per PDF page.
  /// 2-column continuous roll for TVS LP 46 DLITE.
  ///
  /// `mediaHeightMm` is set to `labelHeightMm` as a per-row reference;
  /// the actual PDF page height is calculated dynamically by the layout
  /// engine based on how many labels the user requests.
  static const profile50x35TwoColumn = LabelPrinterProfile(
    id: '50x35_2up',
    name: '50x35 mm (2 Across)',
    mediaWidthMm: 104.0,
    mediaHeightMm: 35.0,
    labelWidthMm: 50.0,
    labelHeightMm: 35.0,
    columns: 2,
    horizontalGapMm: 2.0,
    verticalGapMm: 0.0,
    leftMarginMm: 1.0,
    rightMarginMm: 1.0,
    topMarginMm: 0.0,
    bottomMarginMm: 0.0,
    pageModel: LabelPageModel.multiColumnMedia,
  );

  static const profile50x50Single = LabelPrinterProfile(
    id: '50x50',
    name: '50x50 mm',
    mediaWidthMm: 50.0,
    mediaHeightMm: 50.0,
    labelWidthMm: 50.0,
    labelHeightMm: 50.0,
    columns: 1,
    horizontalGapMm: 0.0,
    pageModel: LabelPageModel.singleLabel,
  );

  static const List<LabelPrinterProfile> predefined = [
    profile50x35Single,
    profile50x35TwoColumn,
    profile50x50Single,
  ];
}
