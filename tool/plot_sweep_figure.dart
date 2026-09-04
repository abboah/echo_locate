// Figure generator for the report — not part of the app.
//
// Usage:
//   dart run tool/plot_sweep_figure.dart <capture.wav> [--out=docs/figures/figure-4-7.svg]
//
// Draws the three stages of the acoustic pipeline from ONE real capture:
// the recorded sweep, the matched-filter output that turns it into an
// impulse response, and the Schroeder decay curve with the straight line
// whose slope IS the RT60 the classifier consumes.
//
// Every number it draws comes from the app's own classes — ChirpGenerator,
// CrossCorrelationService and ReverbAnalyzer — so the figure cannot drift
// from what the running system computes. It plots a recording and nothing
// else: there is no synthetic mode, because a fabricated "capture" in an
// evaluation chapter would be a fabricated measurement.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:echo_locate/services/acoustic/reverb_analyzer.dart';
import 'package:echo_locate/services/dsp/chirp_generator.dart';
import 'package:echo_locate/services/dsp/chirp_params.dart';
import 'package:echo_locate/services/dsp/cross_correlation_service.dart';

// Report palette: the project's Ink and Coral on white, since the figure is
// printed rather than themed.
const _ink = '#1C1B1A';
const _coral = '#FB5B47';
const _grid = '#DAD7D2';
const _muted = '#6B6864';
const _font = 'Segoe UI, Helvetica, Arial, sans-serif';

const _width = 1040.0;
const _left = 84.0;
const _right = 26.0;
const _panelHeight = 200.0;
const _panelGap = 64.0;
const _firstTop = 44.0;

double get _plotWidth => _width - _left - _right;
double _panelTop(int index) => _firstTop + index * (_panelHeight + _panelGap);

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/plot_sweep_figure.dart <capture.wav> '
      '[--out=<file.svg>]',
    );
    exit(1);
  }

  var outPath = 'docs/figures/figure-4-7.svg';
  var full = false;
  for (final a in args) {
    if (a.startsWith('--out=')) outPath = a.substring('--out='.length);
    if (a == '--full') full = true;
  }

  final capture = _readWav(positional.first);
  stdout.writeln(
    'capture: ${positional.first}\n'
    '  sampleRate=${capture.sampleRate} samples=${capture.samples.length} '
    'duration=${(capture.samples.length / capture.sampleRate).toStringAsFixed(2)}s',
  );

  const params = ChirpParams();
  if (capture.sampleRate != params.sampleRate) {
    stderr.writeln(
      'WARNING: capture is ${capture.sampleRate}Hz but the chirp template is '
      '${params.sampleRate}Hz. The matched filter will not compress properly.',
    );
  }

  // Stage 2 — the app's own matched filter, against the app's own template.
  final template = const ChirpGenerator().generate(params);
  final response = const CrossCorrelationService().correlate(
    capture.samples,
    template,
  );
  // Correlation index i is lag i - (template.length - 1), so this is where
  // t=0 of the recording sits in the correlation array.
  final lagZero = template.length - 1;

  // Stage 3 — the analyzer the classifier actually calls.
  final features = const ReverbAnalyzer().analyze(
    impulseResponse: response,
    sampleRate: capture.sampleRate,
  );
  final fit = _refit(response, capture.sampleRate);

  if (features == null || fit == null || fit.start < 0) {
    stderr.writeln(
      '\nNO USABLE DECAY. ReverbAnalyzer refused this capture, so panel (c) '
      'has no fitted line.\n'
      'Usual causes: the room was not quiet for the whole tail, the capture '
      'ended before the decay finished (reverbTail too short for the space), '
      'or the chirp never sounded. Re-capture rather than publish this one.',
    );
  } else {
    stdout.writeln(
      '\nReverbAnalyzer output (these are the caption numbers):\n'
      '  RT60 = ${features.rt60Seconds.toStringAsFixed(3)} s\n'
      '  EDT  = ${features.earlyDecayTimeSeconds.toStringAsFixed(3)} s\n'
      '  EDT/RT60 ratio = '
      '${(features.earlyDecayTimeSeconds / features.rt60Seconds).toStringAsFixed(2)}\n'
      '  fit r2 = ${features.fitQuality.toStringAsFixed(3)}\n'
      '  fitted span = ${features.decayRangeDb.toStringAsFixed(1)} dB',
    );
    // Self-check: the line this tool draws must be the line the analyzer fit.
    final drawnRt60 = -60.0 / fit.slope;
    if ((drawnRt60 - features.rt60Seconds).abs() > 1e-6) {
      stderr.writeln(
        'WARNING: drawn slope implies RT60=${drawnRt60.toStringAsFixed(3)}s but '
        'ReverbAnalyzer reports ${features.rt60Seconds.toStringAsFixed(3)}s — '
        'this tool has drifted from the analyzer.',
      );
    }
  }

  final svg = _buildSvg(
    capture: capture,
    response: response,
    lagZero: lagZero,
    full: full,
    fit: fit,
    rt60: features?.rt60Seconds,
    edt: features?.earlyDecayTimeSeconds,
    rSquared: features?.fitQuality,
  );

  final out = File(outPath);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(svg);
  stdout.writeln('\nwrote ${out.path}');
}

// ---------------------------------------------------------------- WAV input

class _Capture {
  _Capture(this.samples, this.sampleRate);
  final Float64List samples;
  final int sampleRate;
}

_Capture _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final header = ByteData.sublistView(bytes);
  final sampleRate = header.getUint32(24, Endian.little);
  final bitsPerSample = header.getUint16(34, Endian.little);
  if (bitsPerSample != 16) {
    stderr.writeln('Only 16-bit PCM WAV is supported (got $bitsPerSample-bit).');
    exit(1);
  }
  final declared = header.getUint32(40, Endian.little);
  // A dump interrupted mid-write can declare more data than it holds.
  final dataSize = math.min(declared, bytes.length - 44);
  final count = dataSize ~/ 2;
  final data = ByteData.sublistView(bytes, 44, 44 + count * 2);
  final samples = Float64List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return _Capture(samples, sampleRate);
}

// ------------------------------------------------------------- decay re-fit
//
// ReverbAnalyzer returns features, not the curve it fitted them from, and the
// figure has to draw the curve. This mirrors its method exactly — same onset
// rule, same backward integration, same -5/-25dB window — and main() asserts
// the resulting slope reproduces the analyzer's RT60, so a change there that
// is not mirrored here surfaces as a warning rather than a wrong figure.

class _Fit {
  _Fit({
    required this.curveDb,
    required this.onset,
    required this.start,
    required this.end,
    required this.slope,
    required this.intercept,
  });
  final Float64List curveDb;
  final int onset;

  /// Index the fit ran from, or -1 when no fit was possible.
  final int start;
  final int end;
  final double slope;
  final double intercept;
}

_Fit? _refit(Float64List response, int sampleRate) {
  if (response.isEmpty) return null;

  var onset = 0;
  var peak = response[0].abs();
  for (var i = 1; i < response.length; i++) {
    if (response[i].abs() > peak) {
      peak = response[i].abs();
      onset = i;
    }
  }
  final length = response.length - onset;
  if (length < 4) return null;

  final curve = Float64List(length);
  var running = 0.0;
  for (var i = length - 1; i >= 0; i--) {
    final s = response[onset + i];
    running += s * s;
    curve[i] = running;
  }
  final total = curve[0];
  if (total <= 0) return null;
  for (var i = 0; i < length; i++) {
    curve[i] = curve[i] <= 0
        ? -double.infinity
        : 10 * math.log(curve[i] / total) / math.ln10;
  }

  _Fit unfitted() => _Fit(
    curveDb: curve,
    onset: onset,
    start: -1,
    end: -1,
    slope: 0,
    intercept: 0,
  );

  const analyzer = ReverbAnalyzer();
  final start = _firstAtOrBelow(curve, analyzer.upperDb);
  final end = _firstAtOrBelow(curve, analyzer.lowerDb);
  if (start == null || end == null || end <= start + 2) return unfitted();
  if (end > curve.length * analyzer.maximumFitPositionInCapture) {
    return unfitted();
  }
  if (curve[start] - curve[end] < analyzer.minimumDecayDb) return unfitted();

  var sumT = 0.0, sumL = 0.0, sumTT = 0.0, sumTL = 0.0;
  final n = end - start + 1;
  for (var i = start; i <= end; i++) {
    final t = i / sampleRate;
    sumT += t;
    sumL += curve[i];
    sumTT += t * t;
    sumTL += t * curve[i];
  }
  final denom = n * sumTT - sumT * sumT;
  if (denom == 0) return unfitted();
  final slope = (n * sumTL - sumT * sumL) / denom;
  if (slope >= 0) return unfitted();

  return _Fit(
    curveDb: curve,
    onset: onset,
    start: start,
    end: end,
    slope: slope,
    intercept: (sumL - slope * sumT) / n,
  );
}

int? _firstAtOrBelow(Float64List curve, double level) {
  for (var i = 0; i < curve.length; i++) {
    if (curve[i] <= level) return i;
  }
  return null;
}

// -------------------------------------------------------------- SVG drawing

String _buildSvg({
  required _Capture capture,
  required Float64List response,
  required int lagZero,
  required bool full,
  required _Fit? fit,
  required double? rt60,
  required double? edt,
  required double? rSquared,
}) {
  final captureSeconds = capture.samples.length / capture.sampleRate;

  // Panels (a) and (b) share a time window. Cropping it to the part of the
  // recording that contains signal is what makes the sweep legible at all:
  // roughly 300ms of playback latency and a second of silent tail otherwise
  // take three quarters of the width and show nothing. --full opts out, for
  // when the silence is itself the point (a capture that missed its chirp).
  var fromSeconds = 0.0;
  var toSeconds = captureSeconds;
  if (!full && fit != null && rt60 != null) {
    final onsetSeconds = (fit.onset - lagZero) / capture.sampleRate;
    fromSeconds = math.max(0, onsetSeconds - 0.12);
    toSeconds = math.min(
      captureSeconds,
      onsetSeconds + math.max(0.5, 1.5 * rt60),
    );
  }

  final height = _panelTop(2) + _panelHeight + 58;
  final b = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_width.toStringAsFixed(0)}" '
      'height="${height.toStringAsFixed(0)}" '
      'viewBox="0 0 ${_width.toStringAsFixed(0)} ${height.toStringAsFixed(0)}" '
      'font-family="$_font">',
    )
    ..writeln('<rect width="100%" height="100%" fill="#FFFFFF"/>');

  _panelA(b, capture, fromSeconds, toSeconds);
  _panelB(b, capture, response, lagZero, fromSeconds, toSeconds);
  _panelC(b, capture, fit, rt60, edt, rSquared);

  b.writeln('</svg>');
  return b.toString();
}

/// (a) The recording itself: the emitted sweep arriving after the playback
/// latency, then the room's tail.
void _panelA(
  StringBuffer b,
  _Capture capture,
  double fromSeconds,
  double toSeconds,
) {
  final top = _panelTop(0);
  final samples = capture.samples;
  final rate = capture.sampleRate;
  final firstSample = (fromSeconds * rate).floor().clamp(0, samples.length);
  final lastSample = (toSeconds * rate).ceil().clamp(0, samples.length);

  var peak = 0.0;
  for (var i = firstSample; i < lastSample; i++) {
    if (samples[i].abs() > peak) peak = samples[i].abs();
  }
  final span = peak == 0 ? 1.0 : peak * 1.08;

  _frame(
    b,
    top,
    '(a)  Captured sweep — microphone recording',
    'amplitude (full scale)',
  );
  _xAxis(b, top, fromSeconds, toSeconds, (v) => (v * 1000).round().toString());
  _xLabel(b, top, 'time from start of capture (ms)');
  _yAxis(b, top, -span, span, (v) => v.toStringAsFixed(1), ticks: 4);

  // Min/max per pixel column — one point per sample would be 130k points of
  // solid ink, and the envelope is what the eye reads anyway.
  final columns = _plotWidth.round();
  final visible = lastSample - firstSample;
  final path = StringBuffer();
  for (var c = 0; c < columns; c++) {
    final from = firstSample + (c * visible / columns).floor();
    final to = math.min(
      lastSample,
      firstSample + ((c + 1) * visible / columns).ceil(),
    );
    if (from >= to) continue;
    var lo = samples[from];
    var hi = samples[from];
    for (var i = from; i < to; i++) {
      if (samples[i] < lo) lo = samples[i];
      if (samples[i] > hi) hi = samples[i];
    }
    final x = (_left + c).toStringAsFixed(1);
    path.write(
      'M$x,${_mapY(hi, -span, span, top).toStringAsFixed(1)} '
      'L$x,${_mapY(lo, -span, span, top).toStringAsFixed(1)} ',
    );
  }
  b.writeln(
    '<path d="${path.toString().trim()}" stroke="$_ink" stroke-width="1" '
    'opacity="0.85"/>',
  );
}

/// (b) The same recording after matched filtering — the sweep compressed to
/// an impulse, which is the room's impulse response.
void _panelB(
  StringBuffer b,
  _Capture capture,
  Float64List response,
  int lagZero,
  double fromSeconds,
  double toSeconds,
) {
  final top = _panelTop(1);
  final rate = capture.sampleRate;

  var peak = 0.0;
  for (final v in response) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak == 0) peak = 1;

  _frame(
    b,
    top,
    '(b)  Matched-filter output — the room impulse response',
    'correlation (normalised)',
  );
  _xAxis(b, top, fromSeconds, toSeconds, (v) => (v * 1000).round().toString());
  _xLabel(b, top, 'time from start of capture (ms)');
  _yAxis(b, top, 0, 1.05, (v) => v.toStringAsFixed(2), ticks: 3);

  final columns = _plotWidth.round();
  final window = toSeconds - fromSeconds;
  final baseline = _mapY(0, 0, 1.05, top).toStringAsFixed(1);
  final path = StringBuffer();
  var onsetIndex = lagZero;
  var onsetValue = 0.0;
  for (var c = 0; c < columns; c++) {
    final from =
        ((fromSeconds + c * window / columns) * rate).floor() + lagZero;
    final to = math.min(
      response.length,
      ((fromSeconds + (c + 1) * window / columns) * rate).ceil() + lagZero,
    );
    if (from < 0 || from >= to) continue;
    var hi = 0.0;
    for (var i = from; i < to; i++) {
      final v = response[i].abs();
      if (v > hi) hi = v;
      if (v > onsetValue) {
        onsetValue = v;
        onsetIndex = i;
      }
    }
    final x = (_left + c).toStringAsFixed(1);
    path.write(
      'M$x,$baseline L$x,${_mapY(hi / peak, 0, 1.05, top).toStringAsFixed(1)} ',
    );
  }
  b.writeln(
    '<path d="${path.toString().trim()}" stroke="$_ink" stroke-width="1" '
    'opacity="0.8"/>',
  );

  // Mark the direct arrival: it is both the compression the matched filter
  // buys and the t=0 the decay integration starts from.
  final onsetSeconds = (onsetIndex - lagZero) / rate;
  final x = _mapX(onsetSeconds, fromSeconds, toSeconds, _left);
  b
    ..writeln(
      '<line x1="${x.toStringAsFixed(1)}" y1="${top.toStringAsFixed(1)}" '
      'x2="${x.toStringAsFixed(1)}" '
      'y2="${(top + _panelHeight).toStringAsFixed(1)}" '
      'stroke="$_coral" stroke-width="1.4" stroke-dasharray="4 3"/>',
    )
    ..writeln(
      _text(
        x + 8,
        top + 16,
        'direct arrival, ${(onsetSeconds * 1000).toStringAsFixed(0)} ms',
        fill: _coral,
        size: 12.5,
      ),
    );
}

/// (c) Schroeder backward integration of (b), and the straight line whose
/// slope extrapolates to RT60.
void _panelC(
  StringBuffer b,
  _Capture capture,
  _Fit? fit,
  double? rt60,
  double? edt,
  double? rSquared,
) {
  final top = _panelTop(2);
  final rate = capture.sampleRate;

  _frame(
    b,
    top,
    '(c)  Schroeder decay curve and fitted T20 slope',
    'energy remaining (dB)',
  );

  if (fit == null) {
    b.writeln(
      _text(
        _left + 16,
        top + _panelHeight / 2,
        'no decay curve — the capture contained no impulse',
        fill: _muted,
        size: 14,
      ),
    );
    return;
  }

  final curve = fit.curveDb;
  // Where the fitted line reads 0dB, and where it reaches -60dB. The gap
  // between them IS RT60, so anchoring the window on the crossing keeps the
  // annotation and the geometry telling the same story.
  final hasFit = fit.start >= 0;
  final tZero = hasFit ? -fit.intercept / fit.slope : 0.0;
  final tCross = hasFit ? tZero + (rt60 ?? 0) : 0.0;
  final maxSeconds = hasFit
      ? math.min(math.max(tCross * 1.12, 0.05), curve.length / rate)
      : curve.length / rate;
  const minDb = -70.0;
  const maxDb = 10.0;

  // Decimals follow the window: a fast decay spans tens of milliseconds, and
  // at two decimals every tick there rounds to the same two or three values.
  final decimals = maxSeconds < 0.02
      ? 4
      : maxSeconds < 0.2
      ? 3
      : 2;
  _xAxis(b, top, 0, maxSeconds, (v) => v.toStringAsFixed(decimals));
  _xLabel(b, top, 'time from direct arrival (s)');
  _yAxis(b, top, minDb, maxDb, (v) => v.toStringAsFixed(0), ticks: 8);

  // The measured curve.
  final columns = _plotWidth.round();
  final points = <String>[];
  for (var c = 0; c <= columns; c++) {
    final t = c * maxSeconds / columns;
    final i = (t * rate).round();
    if (i >= curve.length) break;
    final v = curve[i];
    if (!v.isFinite || v < minDb) break;
    points.add(
      '${_mapX(t, 0, maxSeconds, _left).toStringAsFixed(1)},'
      '${_mapY(v, minDb, maxDb, top).toStringAsFixed(1)}',
    );
  }
  b.writeln(
    '<polyline points="${points.join(' ')}" fill="none" stroke="$_ink" '
    'stroke-width="1.8"/>',
  );

  if (!hasFit) {
    b.writeln(
      _text(
        _left + 16,
        top + 30,
        'no fit — decay rejected by ReverbAnalyzer',
        fill: _coral,
        size: 13,
      ),
    );
    return;
  }

  double lineY(double t) => fit.slope * t + fit.intercept;
  String px(double t) => _mapX(t, 0, maxSeconds, _left).toStringAsFixed(1);
  String py(double v) => _mapY(v, minDb, maxDb, top).toStringAsFixed(1);

  final tStart = fit.start / rate;
  final tEnd = fit.end / rate;

  // Solid over the stretch actually fitted, dashed where it is extrapolated
  // — the distinction the whole method rests on.
  b
    ..writeln(
      '<line x1="${px(tStart)}" y1="${py(lineY(tStart))}" '
      'x2="${px(tEnd)}" y2="${py(lineY(tEnd))}" '
      'stroke="$_coral" stroke-width="2.4"/>',
    )
    ..writeln(
      '<line x1="${px(tEnd)}" y1="${py(lineY(tEnd))}" '
      'x2="${px(math.min(tCross, maxSeconds))}" '
      'y2="${py(lineY(math.min(tCross, maxSeconds)))}" '
      'stroke="$_coral" stroke-width="1.6" stroke-dasharray="6 4"/>',
    );

  // The -5 and -25dB window, stated rather than implied.
  for (final level in <double>[-5, -25]) {
    b
      ..writeln(
        '<line x1="$_left" y1="${py(level)}" '
        'x2="${(_width - _right).toStringAsFixed(1)}" y2="${py(level)}" '
        'stroke="$_coral" stroke-width="0.8" stroke-dasharray="2 4" '
        'opacity="0.7"/>',
      )
      ..writeln(
        _text(
          _width - _right - 6,
          _mapY(level, minDb, maxDb, top) - 5,
          '${level.toStringAsFixed(0)} dB',
          fill: _coral,
          size: 11.5,
          anchor: 'end',
        ),
      );
  }

  if (rt60 != null && tCross <= maxSeconds) {
    b
      ..writeln(
        '<line x1="${px(tCross)}" y1="${top.toStringAsFixed(1)}" '
        'x2="${px(tCross)}" y2="${py(-60)}" stroke="$_muted" '
        'stroke-width="1" stroke-dasharray="3 3"/>',
      )
      ..writeln(
        '<circle cx="${px(tCross)}" cy="${py(-60)}" r="3.5" fill="$_coral"/>',
      )
      ..writeln(
        _text(
          _mapX(tCross, 0, maxSeconds, _left) - 10,
          _mapY(-60, minDb, maxDb, top) - 10,
          'RT60 = ${rt60.toStringAsFixed(2)} s',
          fill: _ink,
          size: 13,
          anchor: 'end',
          weight: '600',
          halo: true,
        ),
      );
  }

  if (edt != null && rSquared != null && rt60 != null) {
    b.writeln(
      _text(
        _left + 12,
        top + _panelHeight - 14,
        'EDT ${edt.toStringAsFixed(2)} s  |  '
        'EDT/RT60 ${(edt / rt60).toStringAsFixed(2)}  |  '
        'r² ${rSquared.toStringAsFixed(3)}',
        fill: _muted,
        size: 12.5,
      ),
    );
  }
}

// ------------------------------------------------------------ axis plumbing

double _mapX(double v, double lo, double hi, double x0) =>
    x0 + (v - lo) / (hi - lo) * _plotWidth;

double _mapY(double v, double lo, double hi, double top) =>
    top + _panelHeight - (v - lo) / (hi - lo) * _panelHeight;

void _frame(StringBuffer b, double top, String title, String yLabel) {
  final midY = (top + _panelHeight / 2).toStringAsFixed(1);
  final labelX = (_left - 58).toStringAsFixed(1);
  b
    ..writeln(
      _text(_left, top - 16, title, fill: _ink, size: 14.5, weight: '600'),
    )
    ..writeln(
      '<rect x="$_left" y="${top.toStringAsFixed(1)}" '
      'width="${_plotWidth.toStringAsFixed(1)}" height="$_panelHeight" '
      'fill="none" stroke="$_grid" stroke-width="1"/>',
    )
    ..writeln(
      '<text x="$labelX" y="$midY" fill="$_muted" font-size="12.5" '
      'text-anchor="middle" transform="rotate(-90 $labelX $midY)">'
      '${_escape(yLabel)}</text>',
    );
}

void _xAxis(
  StringBuffer b,
  double top,
  double lo,
  double hi,
  String Function(double) label, {
  int ticks = 8,
}) {
  for (var i = 0; i <= ticks; i++) {
    final v = lo + (hi - lo) * i / ticks;
    final x = _mapX(v, lo, hi, _left);
    if (i > 0 && i < ticks) {
      b.writeln(
        '<line x1="${x.toStringAsFixed(1)}" y1="${top.toStringAsFixed(1)}" '
        'x2="${x.toStringAsFixed(1)}" '
        'y2="${(top + _panelHeight).toStringAsFixed(1)}" stroke="$_grid" '
        'stroke-width="0.7"/>',
      );
    }
    b.writeln(
      _text(
        x,
        top + _panelHeight + 17,
        label(v),
        fill: _muted,
        size: 11.5,
        anchor: 'middle',
      ),
    );
  }
}

void _xLabel(StringBuffer b, double top, String text) {
  b.writeln(
    _text(
      _left + _plotWidth / 2,
      top + _panelHeight + 38,
      text,
      fill: _muted,
      size: 12.5,
      anchor: 'middle',
    ),
  );
}

void _yAxis(
  StringBuffer b,
  double top,
  double lo,
  double hi,
  String Function(double) label, {
  int ticks = 4,
}) {
  for (var i = 0; i <= ticks; i++) {
    final v = lo + (hi - lo) * i / ticks;
    final y = _mapY(v, lo, hi, top);
    if (i > 0 && i < ticks) {
      b.writeln(
        '<line x1="$_left" y1="${y.toStringAsFixed(1)}" '
        'x2="${(_width - _right).toStringAsFixed(1)}" '
        'y2="${y.toStringAsFixed(1)}" stroke="$_grid" stroke-width="0.7"/>',
      );
    }
    b.writeln(
      _text(
        _left - 10,
        y + 4,
        label(v),
        fill: _muted,
        size: 11.5,
        anchor: 'end',
      ),
    );
  }
}

String _text(
  double x,
  double y,
  String content, {
  required String fill,
  required double size,
  String anchor = 'start',
  String weight = '400',
  // Paints the glyphs over a white outline of themselves, so a label that
  // lands on a gridline stays readable instead of being struck through.
  bool halo = false,
}) =>
    '<text x="${x.toStringAsFixed(1)}" y="${y.toStringAsFixed(1)}" '
    'fill="$fill" font-size="$size" text-anchor="$anchor" '
    'font-weight="$weight"'
    '${halo ? ' paint-order="stroke" stroke="#FFFFFF" stroke-width="3.5" '
          'stroke-linejoin="round"' : ''}'
    '>${_escape(content)}</text>';

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
