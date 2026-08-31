import 'package:echo_locate/services/sensing/analyser_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frames one analyser cycle hands out, in order.
List<Analyser> _cycle(int count, {double? remainingM}) => [
  for (var i = 0; i < count; i++)
    AnalyserSchedule.analyserFor(index: i, remainingM: remainingM),
];

void main() {
  group('mid-corridor', () {
    test('splits frames evenly between obstacles and signage', () {
      expect(_cycle(6, remainingM: 20), [
        Analyser.objects,
        Analyser.text,
        Analyser.objects,
        Analyser.text,
        Analyser.objects,
        Analyser.text,
      ]);
    });

    test('splits evenly when nothing is measuring the leg', () {
      final cycle = _cycle(6);
      expect(cycle.where((a) => a == Analyser.text).length, 3);
      expect(cycle.where((a) => a == Analyser.objects).length, 3);
    });
  });

  group('arriving at a landmark', () {
    test('gives signage two frames in three', () {
      final cycle = _cycle(6, remainingM: 2);
      expect(cycle.where((a) => a == Analyser.text).length, 4);
    });

    test('never starves obstacle detection', () {
      final cycle = _cycle(9, remainingM: 0);
      expect(cycle.where((a) => a == Analyser.objects).length, 3);
    });

    test('the switch happens at the approach distance, not before', () {
      expect(_cycle(6, remainingM: 4.1).where((a) => a == Analyser.text).length, 3);
      expect(_cycle(6, remainingM: 3.9).where((a) => a == Analyser.text).length, 4);
    });
  });
}
