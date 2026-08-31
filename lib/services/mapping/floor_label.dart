/// What to call a floor when the building index cannot be asked.
///
/// Every screen that lists floors needs this, and each has to work with no
/// connection — the traced plan is on the device, the `floors` row that names
/// it may not be. One definition so two screens cannot disagree about which
/// floor somebody is looking at.
library;

/// Reads a floor's label out of its id: `floor-g` and `gf` both give `G`,
/// `floor-2` gives `2`.
///
/// The ids are minted alongside the index's own labels, so this agrees with
/// the index wherever both exist — and stays readable where only one does.
String floorLabelFromId(String floorId) {
  final normalised = floorId.trim().toLowerCase();
  if (normalised.isEmpty) return '';

  // `gf`, `ground`, `ground-floor`, `floor-g` — the spellings that actually
  // occur, all meaning the same storey.
  if (normalised == 'gf' ||
      normalised == 'g' ||
      normalised.contains('ground') ||
      normalised.endsWith('-g') ||
      normalised.endsWith('_g')) {
    return 'G';
  }

  final tail = normalised.split(RegExp('[-_:]')).last.trim();
  return tail.isEmpty ? floorId : tail.toUpperCase();
}

/// "Ground floor" / "Floor 2" — the label as a sentence, for a row title and
/// for the screen reader.
String floorTitleFor(String label) =>
    label.toUpperCase() == 'G' ? 'Ground floor' : 'Floor $label';
