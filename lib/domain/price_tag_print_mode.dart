enum PriceTagPrintMode {
  /// The legacy A4 sheet printing mode. Tags are laid out in a grid (e.g. 5x10).
  /// Generates a PDF sized to A4 and relies on the OS print dialog.
  a4Sheet,

  /// Direct hardware label printing mode. Tags are generated as a PDF stream
  /// where 1 page = 1 physical label (e.g. 50x35mm), bypassing OS dialogs.
  lp46Direct,
}
