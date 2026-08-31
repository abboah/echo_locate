import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/logger.dart';
import '../../data/repository_mixin.dart';

/// What kind of report this is.
enum FeedbackKind {
  /// Something is broken.
  problem('problem', 'Something is broken'),

  /// The map itself is wrong — a missing door, a room in the wrong place.
  mapError('map_error', 'A map is wrong'),

  /// A suggestion.
  idea('idea', 'An idea');

  const FeedbackKind(this.id, this.label);

  /// Matches the `kind` check constraint on `public.feedback`.
  final String id;
  final String label;
}

/// One report, as the user wrote it.
class FeedbackReport {
  const FeedbackReport({
    required this.kind,
    required this.message,
    this.buildingId,
    this.context = '',
  });

  final FeedbackKind kind;
  final String message;

  /// Which building it is about, when the report is about a map. The reason a
  /// report beats an email: "the route was wrong" cannot be acted on without
  /// knowing which building it was wrong in.
  final String? buildingId;

  /// Device and build string.
  final String context;

  Map<String, dynamic> toJson() => {
    'kind': kind.id,
    'message': message,
    'building_id': buildingId,
    'context': context,
  };

  static FeedbackReport? fromJson(Map<String, dynamic> json) {
    final message = json['message'] as String?;
    if (message == null || message.trim().isEmpty) return null;
    return FeedbackReport(
      kind: FeedbackKind.values.firstWhere(
        (kind) => kind.id == json['kind'],
        orElse: () => FeedbackKind.problem,
      ),
      message: message,
      buildingId: json['building_id'] as String?,
      context: (json['context'] as String?) ?? '',
    );
  }
}

/// Filing a problem report from inside the app.
///
/// Worth more here than in most apps. The people this is built for cannot
/// point at the screen and show somebody what went wrong, and a wrong map is
/// invisible from the outside — the app will confidently guide somebody into a
/// wall and report success. This is the only channel that says otherwise.
abstract class FeedbackRepository {
  /// Files [report]. Queues it on the device if it cannot be sent now.
  ///
  /// Returns whether it reached the server. `false` is not a failure: it means
  /// the report is safely on the device and will go with the next one. The
  /// screen says which happened rather than claiming success either way.
  Future<bool> submit(FeedbackReport report);

  /// Sends anything queued. Called on the next successful submit.
  Future<void> flush();

  /// How many reports are waiting to be sent.
  Future<int> pendingCount();
}

/// Device-local only: the offline build has nowhere to send a report, so it
/// keeps every one. They go out if the app is later pointed at Supabase.
class LocalFeedbackRepository with RepositoryMixin implements FeedbackRepository {
  const LocalFeedbackRepository();

  static const String _prefix = 'feedback_pending';

  Box<dynamic> get _box => Hive.box(repoCacheBoxName);

  static String _key() =>
      '$_prefix:${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<bool> submit(FeedbackReport report) async =>
      runOperation('feedback_submit_local', () async {
        await _box.put(_key(), jsonEncode(report.toJson()));
        return false;
      });

  @override
  Future<void> flush() async {}

  @override
  Future<int> pendingCount() async => _pending().length;

  List<String> _pending() => [
    for (final key in _box.keys)
      if (key is String && key.startsWith('$_prefix:')) key,
  ];
}

/// Sends to `public.feedback`, queueing on the device when that fails.
class SupabaseFeedbackRepository
    with RepositoryMixin
    implements FeedbackRepository {
  SupabaseFeedbackRepository(this._client);

  final SupabaseClient _client;

  static const String _prefix = 'feedback_pending';

  Box<dynamic> get _box => Hive.box(repoCacheBoxName);

  @override
  Future<bool> submit(FeedbackReport report) async {
    try {
      await _send(report);
    } catch (error) {
      // A report is somebody taking the trouble to tell you something is
      // wrong. Losing it because the campus wifi dropped is the one outcome
      // worth going out of the way to prevent.
      AppLogger.warn('Feedback queued for later: $error');
      await _queue(report);
      return false;
    }
    // Only once something has got through is it worth retrying the backlog.
    unawaitedFlush();
    return true;
  }

  Future<void> _send(FeedbackReport report) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const OperationFailure('Not signed in');
    await _client.from('feedback').insert({
      ...report.toJson(),
      'user_id': user.id,
    });
  }

  Future<void> _queue(FeedbackReport report) async {
    try {
      await _box.put(
        '$_prefix:${DateTime.now().microsecondsSinceEpoch}',
        jsonEncode(report.toJson()),
      );
    } catch (error) {
      AppLogger.error('Could not queue feedback', error);
    }
  }

  /// Fire-and-forget flush, so submitting never waits on the backlog.
  void unawaitedFlush() {
    flush().catchError((Object error) {
      AppLogger.warn('Feedback flush failed: $error');
    });
  }

  @override
  Future<void> flush() async {
    final keys = [
      for (final key in _box.keys)
        if (key is String && key.startsWith('$_prefix:')) key,
    ];
    for (final key in keys) {
      final raw = _box.get(key);
      if (raw is! String) {
        await _box.delete(key);
        continue;
      }
      final report = FeedbackReport.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (report == null) {
        await _box.delete(key);
        continue;
      }
      // Stop at the first failure: the rest will fail the same way, and
      // hammering a dead connection once per queued report helps nobody.
      await _send(report);
      await _box.delete(key);
    }
  }

  @override
  Future<int> pendingCount() async => [
    for (final key in _box.keys)
      if (key is String && key.startsWith('$_prefix:')) key,
  ].length;
}
