import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../core/models/room_plan.dart';
import '../../core/utils/logger.dart';
import '../../data/repository_mixin.dart';

/// Storage for traced room geometry.
///
/// Separate from [RouteRepository] rather than bolted onto it, because the two
/// hold different things about the same building and are produced by different
/// people at different times: `RouteRepository` holds landmarks and recorded
/// walks — the data guidance runs on — and this holds room *areas*, which are
/// what gets drawn and what makes door counting possible. A building can have
/// either, both, or neither.
abstract class RoomPlanRepository {
  /// The traced rooms for one floor, or null when nobody has traced it.
  Future<RoomPlan?> planFor(String buildingId, String floorId);

  /// Every floor of a building that has been traced.
  Future<List<RoomPlan>> plansOf(String buildingId);

  /// Every traced floor held on this device, across all buildings.
  ///
  /// What the Maps tab is a list of. Asking building by building cannot answer
  /// it — that needs the building index first, which is exactly the thing that
  /// is unavailable in the case Maps exists for: a phone with no connection,
  /// holding floors somebody traced.
  ///
  /// Device-local in every implementation, drafts excluded. A floor is on this
  /// list because it is finished and stored here, not because it is published.
  Future<List<RoomPlan>> allPlans();

  /// Stores a plan, replacing whatever that floor had.
  ///
  /// Replace rather than merge: two contributors tracing the same floor are
  /// producing two opinions of the same geometry, and merging polygons is not
  /// a thing that can be done sensibly without asking somebody which is right.
  /// Last write wins, and the plan is small enough to retrace.
  Future<void> save(RoomPlan plan);

  Future<void> delete(String buildingId, String floorId);

  /// Keeps the floor as it stands right now, without publishing it.
  ///
  /// Tracing a floor is twenty minutes of standing in front of a board, and
  /// until [save] succeeded none of it existed anywhere but in the Bloc — a
  /// crash, a swipe-away or a flat battery took the lot. A draft is written on
  /// every structural change, so at worst the room being drawn is lost.
  ///
  /// Always device-local, in every implementation: a draft is by definition the
  /// work somebody has not chosen to share, and pushing half a floor to
  /// everybody else's phone is not a recovery mechanism.
  Future<void> saveDraft(RoomPlan plan);

  /// The unpublished draft for this floor, if there is one.
  Future<RoomPlan?> draftFor(String buildingId, String floorId);

  /// Drops the draft once the floor is safely published.
  Future<void> clearDraft(String buildingId, String floorId);
}

/// On-device storage, in the hive box the repositories already share.
///
/// The only implementation for now, and deliberately so. A Supabase table would
/// let plans be crowdsourced — which is the point of the app — but tracing has
/// to be *usable* before sharing it means anything, and this makes it usable
/// today, offline, on a phone with no ARCore and a flaky campus connection.
/// The interface above is what a `SupabaseRoomPlanRepository` implements when
/// the table exists; nothing calling it needs to change.
///
/// Stored as JSON strings rather than as maps: Hive can hold a `Map`, but the
/// nested lists of freezed models inside a plan are not types it knows, and it
/// throws `Cannot write, unknown type: _Room` at the moment of saving — the
/// same failure the caching mixin documents. Encoding once at the boundary
/// keeps that impossible.
class LocalRoomPlanRepository
    with RepositoryMixin
    implements RoomPlanRepository {
  const LocalRoomPlanRepository();

  static const String _prefix = 'room_plan';

  /// Drafts live under their own prefix so an unfinished floor can never
  /// overwrite the published one it is a draft *of* — the failure would be
  /// silent and would cost exactly the work this is here to protect.
  static const String _draftPrefix = 'room_plan_draft';

  static String _key(String buildingId, String floorId) =>
      '$_prefix:$buildingId:$floorId';

  static String _draftKey(String buildingId, String floorId) =>
      '$_draftPrefix:$buildingId:$floorId';

  Box<dynamic> get _box => Hive.box(repoCacheBoxName);

  @override
  Future<RoomPlan?> planFor(String buildingId, String floorId) async =>
      runOperation('planFor', () async {
        return _decode(_box.get(_key(buildingId, floorId)));
      });

  @override
  Future<List<RoomPlan>> plansOf(String buildingId) async =>
      runOperation('plansOf', () async {
        final plans = <RoomPlan>[];
        for (final key in _box.keys) {
          if (key is! String || !key.startsWith('$_prefix:$buildingId:')) {
            continue;
          }
          final plan = _decode(_box.get(key));
          if (plan != null) plans.add(plan);
        }
        return plans;
      });

  @override
  Future<List<RoomPlan>> allPlans() async => runOperation('allPlans', () async {
    final plans = <RoomPlan>[];
    for (final key in _box.keys) {
      // `room_plan_draft:…` does not start with `room_plan:`, so drafts
      // fall out here rather than needing to be filtered afterwards.
      if (key is! String || !key.startsWith('$_prefix:')) continue;
      final plan = _decode(_box.get(key));
      if (plan != null) plans.add(plan);
    }
    return plans;
  });

  @override
  Future<void> save(RoomPlan plan) async =>
      runOperation('saveRoomPlan', () async {
        await _box.put(
          _key(plan.buildingId, plan.floorId),
          jsonEncode(plan.toJson()),
        );
      });

  @override
  Future<void> delete(String buildingId, String floorId) async =>
      runOperation('deleteRoomPlan', () async {
        await _box.delete(_key(buildingId, floorId));
      });

  @override
  Future<void> saveDraft(RoomPlan plan) async => runOperation(
    'saveRoomPlanDraft',
    () async => _box.put(
      _draftKey(plan.buildingId, plan.floorId),
      jsonEncode(plan.toJson()),
    ),
  );

  @override
  Future<RoomPlan?> draftFor(String buildingId, String floorId) async =>
      runOperation(
        'roomPlanDraftFor',
        () async => _decode(_box.get(_draftKey(buildingId, floorId))),
      );

  @override
  Future<void> clearDraft(String buildingId, String floorId) async =>
      runOperation(
        'clearRoomPlanDraft',
        () async => _box.delete(_draftKey(buildingId, floorId)),
      );

  /// A plan that will not decode is treated as absent, not as a crash.
  ///
  /// Schema drift after an app update is the realistic cause, and the cost of
  /// being wrong here is asking somebody to retrace a floor. The cost of
  /// throwing is a screen that cannot open at all.
  /// Reads the JSON string this class writes, and also the bare map the
  /// Supabase repository's offline-first cache used to leave under the very
  /// same key. Both shapes are somebody's traced floor; refusing the older one
  /// would report a plan already on the device as "never traced".
  static RoomPlan? _decode(Object? stored) {
    if (stored == null) return null;
    try {
      final json = stored is String ? jsonDecode(stored) : stored;
      if (json is! Map) return null;
      return RoomPlan.fromJson(Map<String, dynamic>.from(json));
    } catch (error, stack) {
      AppLogger.error('Stored room plan could not be decoded', error, stack);
      return null;
    }
  }
}
