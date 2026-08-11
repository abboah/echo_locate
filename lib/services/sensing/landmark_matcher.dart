import '../../core/models/landmark.dart';

/// Decides whether a line of OCR text denotes a landmark.
///
/// This is the whole positioning system's accept/reject gate: guidance advances
/// a leg the moment this says yes, so a wrong yes walks someone who cannot see
/// through the wrong door, and a wrong no costs a recovery sweep. The two
/// mistakes are not symmetric, and this class is tuned accordingly — see
/// [allowConfusions].
///
/// Deliberately free of ML Kit and camera types so the matching rules can be
/// unit-tested and re-fitted (§10) without hardware.
class LandmarkMatcher {
  const LandmarkMatcher({this.allowConfusions = true});

  /// Whether to accept a single character swapped for one it is commonly
  /// misread as ([_confusions]). Off gives exact-and-alias matching only,
  /// which is the baseline the evaluation compares against.
  final bool allowConfusions;

  /// Characters OCR genuinely swaps, because they are drawn alike. Symmetric;
  /// listed one way round and mirrored in [_confusable].
  ///
  /// The spec allowed any single edit (Levenshtein <= 1). That is unsafe on the
  /// short numeric labels this app is built around: '204' and '205' are one
  /// edit apart, so an arbitrary-edit rule would confidently accept the room
  /// next door. Only shape confusions are admitted, which leaves adjacent room
  /// numbers correctly unmatched.
  static const Map<String, String> _confusions = {
    '0': 'OQD',
    '1': 'IL',
    '2': 'Z',
    '5': 'S',
    '6': 'G',
    '8': 'B',
  };

  static bool _confusable(String a, String b) {
    if (a == b) return true;
    return (_confusions[a]?.contains(b) ?? false) ||
        (_confusions[b]?.contains(a) ?? false);
  }

  /// Whether [read] denotes [landmark].
  ///
  /// Exact and alias hits come from the model itself ([Landmark.matchesExactly])
  /// so the normalisation rule lives in one place.
  bool matches(String read, Landmark landmark) {
    if (landmark.matchesExactly(read)) return true;
    if (!allowConfusions) return false;

    final target = Landmark.normalise(landmark.labelText);
    if (_isConfusedForm(read, target)) return true;
    return landmark.aliases.any((alias) => _isConfusedForm(read, alias));
  }

  /// The landmark [read] denotes, or null when nothing matches — or when more
  /// than one does.
  ///
  /// Ambiguity is refused rather than resolved by ordering. Two landmarks one
  /// confusion apart ('101' and '1O1') are exactly the case where a guess is
  /// most likely wrong, and silence routes the user into the recovery sweep,
  /// which is designed for this.
  Landmark? match(String read, List<Landmark> candidates) {
    // An exact hit is never ambiguous: a sign that reads a landmark's label
    // verbatim denotes it, whatever else it resembles.
    final exact = candidates.where((l) => l.matchesExactly(read)).toList();
    if (exact.length == 1) return exact.first;
    if (exact.length > 1) return null;

    final fuzzy = candidates.where((l) => matches(read, l)).toList();
    return fuzzy.length == 1 ? fuzzy.first : null;
  }

  /// True when [read] is [target] with spacing lost or one character swapped
  /// for a look-alike.
  bool _isConfusedForm(String read, String target) {
    final a = Landmark.normalise(read);
    final b = Landmark.normalise(target);
    if (a == b) return true;

    // OCR splitting one plate across blocks ('2 04') or joining two. Only
    // whitespace differs, so no character has actually been misread.
    if (a.replaceAll(' ', '') == b.replaceAll(' ', '')) return true;

    // Look-alike substitutions. Length must hold: an inserted or dropped
    // character is a different label, not a misread one.
    //
    // The number of substitutions is deliberately not capped. A plate reading
    // '201' can come back as '2Ol' with both characters confused at once, and
    // capping at one would reject it. Safety comes from the restriction to
    // [_confusions], not from a count: '204' and '205' stay unmatched at any
    // number of swaps because 4 and 5 look nothing alike. Where uncapping does
    // make two real landmarks collide, [match] refuses them as ambiguous.
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_confusable(a[i], b[i])) return false;
    }
    return true;
  }
}
