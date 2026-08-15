import 'package:flutter/material.dart';

import '../../core/models/room_plan.dart';
import '../../core/theme/app_colors.dart';

/// Category fills for the schematic — floorplan spec §5.
///
/// Two palettes, not one dimmed. `CLAUDE.md` requires every screen in light and
/// dark, and a fill chosen to read on white does not read on `#141312`: mid
/// greys vanish, and the pure white a staircase gets in light mode glares in
/// dark. So the dark set is rebuilt at the same *hue* with luminance inverted
/// about the surface, which keeps the categories recognisable between themes
/// while both stay legible.
///
/// Coral is deliberately absent. It is the app's single accent and it means
/// "your route" everywhere else; spending it on a room category would make
/// every laboratory look like a destination.
class RoomPalette {
  const RoomPalette._(this._fills, this.outline, this.corridorFill);

  final Map<RoomCategory, Color> _fills;

  /// Wall colour. Every room gets it, so the plan reads as walls with rooms
  /// between them.
  final Color outline;

  /// Circulation space — floor, not room. Kept distinct from the page
  /// background so a corridor reads as somewhere you can walk rather than as a
  /// hole in the plan.
  final Color corridorFill;

  /// Light theme: every fill sits **above** the luminance dead band, so near
  /// black label ink clears AA on all of them.
  ///
  /// The band matters. A mid-luminance fill — a saturated mid blue, say — is
  /// too dark for black text and too light for white, and no choice of ink
  /// reaches 4.5:1 on it. The spec's palette is full of them. Since these
  /// rooms carry their codes *inside* the fill, the fill is chosen to make the
  /// text work rather than the other way round: pastels here, near-blacks in
  /// [dark]. Hue still separates the categories, which is what the eye reads.
  static const RoomPalette light = RoomPalette._(
    {
      RoomCategory.lectureHall: Color(0xFFF2D98C),
      RoomCategory.office: Color(0xFFAFCDE8),
      RoomCategory.laboratory: Color(0xFFA8DCC8),
      RoomCategory.auditorium: Color(0xFFD8D4CD),
      RoomCategory.controlRoom: Color(0xFFC4BDB4),
      RoomCategory.commonRoom: Color(0xFFF0CBA0),
      RoomCategory.library: Color(0xFFC9C2EC),
      RoomCategory.boardroom: Color(0xFFEBC9C3),
      RoomCategory.washroom: Color(0xFFE8E6E1),
      RoomCategory.staircase: Color(0xFFF2F0EC),
      RoomCategory.elevator: Color(0xFFD4CFC8),
      RoomCategory.balcony: Color(0xFFEDEBE6),
      RoomCategory.other: Color(0xFFDDDAD4),
    },
    AppColors.ink,
    Color(0xFFFFFFFF),
  );

  /// Dark theme: the same hues, taken **below** the dead band so white ink
  /// clears AA. Not the light fills dimmed — dimming lands them in the band.
  static const RoomPalette dark = RoomPalette._(
    {
      RoomCategory.lectureHall: Color(0xFF6B5518),
      RoomCategory.office: Color(0xFF2B4A63),
      RoomCategory.laboratory: Color(0xFF235347),
      RoomCategory.auditorium: Color(0xFF45413C),
      RoomCategory.controlRoom: Color(0xFF35322E),
      RoomCategory.commonRoom: Color(0xFF6A4826),
      RoomCategory.library: Color(0xFF453E6E),
      RoomCategory.boardroom: Color(0xFF6B4A45),
      RoomCategory.washroom: Color(0xFF33302C),
      RoomCategory.staircase: Color(0xFF3D3A35),
      RoomCategory.elevator: Color(0xFF4E4841),
      RoomCategory.balcony: Color(0xFF302D29),
      RoomCategory.other: Color(0xFF413D38),
    },
    Color(0xFFC9C4BC),
    AppColors.darkElevated,
  );

  static RoomPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The fill for [category].
  ///
  /// Corridors resolve to [corridorFill] rather than to a transparent hole. The
  /// spec maps them to `0x00000000`, which then feeds a luminance test that
  /// reports 0 and paints white label text onto an unpainted white page — the
  /// corridor names, which are the ones a wayfinding map most needs, come out
  /// invisible.
  Color fillFor(RoomCategory category) => category == RoomCategory.corridor
      ? corridorFill
      : _fills[category] ?? _fills[RoomCategory.other]!;

  /// Ink for text drawn on [background] — whichever of near-black and white
  /// actually contrasts better.
  ///
  /// Measured rather than thresholded. A fixed luminance split picks white the
  /// moment a fill crosses it, including for fills where black would in fact
  /// have contrasted better, and the label silently drops below AA. Computing
  /// both ratios is two multiplications and cannot make that mistake.
  ///
  /// `room_plan_view_test.dart` asserts every category clears AA in both
  /// themes; this function is only half of that guarantee, the palettes being
  /// the other half.
  Color labelOn(Color background) =>
      contrastRatio(darkInk, background) >= contrastRatio(lightInk, background)
      ? darkInk
      : lightInk;

  static const Color darkInk = Color(0xFF1A1A1A);
  static const Color lightInk = Color(0xFFFFFFFF);

  /// WCAG 2.1 contrast ratio, 1:1 to 21:1. AA wants 4.5 for body text.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// What the legend calls each category — see [RoomCategory.title], which is
  /// the one definition, so the legend and an unnamed room's name cannot drift
  /// apart.
  static String labelFor(RoomCategory category) => category.title;

  /// Categories present on this floor, in a stable order, corridors excluded.
  ///
  /// The legend generates itself from what is actually drawn — the mapper never
  /// authors one, and it can never fall out of step with the plan. Corridors
  /// are left out because they are not a room type anybody looks up; they are
  /// the space between.
  static List<RoomCategory> legendFor(Iterable<Room> rooms) {
    final present = rooms.map((r) => r.category).toSet()
      ..remove(RoomCategory.corridor);
    return [
      for (final category in RoomCategory.values)
        if (present.contains(category)) category,
    ];
  }
}
