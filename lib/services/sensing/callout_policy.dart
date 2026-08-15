import 'package:equatable/equatable.dart';

import 'detected_obstacle.dart';

/// What Assist Mode announces: card text + spoken sentence + urgency.
class AssistCallout extends Equatable {
  const AssistCallout({
    required this.title,
    required this.detail,
    required this.urgent,
    required this.label,
  });

  /// Card headline, e.g. "Furniture on your left".
  final String title;

  /// Card subline / proximity, e.g. "very close".
  final String detail;

  /// Very-close obstacles interrupt and repeat sooner.
  final bool urgent;

  /// Raw label, used for cooldown identity and icon choice.
  final String label;

  String get spoken => '$title, $detail';

  @override
  List<Object?> get props => [title, detail, urgent, label];
}

/// Turns raw per-frame detections into occasional, useful speech.
///
/// Rules: nearest (tallest) obstacle wins; ignore far-away noise; don't
/// repeat the same announcement while it stays true (cooldown, shorter when
/// urgent). Without this, TTS babbles "furniture, furniture, furniture"
/// three times a second and the feature is unusable.
class CalloutPolicy {
  static const _cooldown = Duration(seconds: 5);
  static const _urgentCooldown = Duration(seconds: 2);

  final Map<String, DateTime> _lastAnnounced = {};

  AssistCallout? evaluate(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) return null;

    final nearest = obstacles.reduce(
      (a, b) => a.heightFraction >= b.heightFraction ? a : b,
    );

    // Too small/far to matter — stay quiet.
    if (nearest.heightFraction < 0.15) return null;

    final urgent = nearest.heightFraction >= 0.55;
    final detail = urgent
        ? 'very close'
        : nearest.heightFraction >= 0.30
        ? 'close'
        : 'a few steps ahead';

    final position = switch (nearest.position) {
      ObstaclePosition.left => 'on your left',
      ObstaclePosition.right => 'on your right',
      ObstaclePosition.center => 'ahead',
    };

    final key = '${nearest.label}:$position';
    final last = _lastAnnounced[key];
    final now = DateTime.now();
    if (last != null &&
        now.difference(last) < (urgent ? _urgentCooldown : _cooldown)) {
      return null;
    }
    _lastAnnounced[key] = now;

    final thing = nearest.label[0].toUpperCase() + nearest.label.substring(1);
    return AssistCallout(
      title: '$thing $position',
      detail: detail,
      urgent: urgent,
      label: nearest.label,
    );
  }

  void reset() => _lastAnnounced.clear();
}
