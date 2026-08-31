import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/room_plan.dart';
import '../../core/utils/logger.dart';
import '../../data/repository_mixin.dart';
import 'room_plan_repository.dart';

/// Traced room plans, shared through Supabase.
///
/// The crowdsourcing half of the room layer: one contributor traces a floor off
/// the board on its wall, and everybody navigating that building afterwards gets
/// the geometry — including the door counts that let guidance say "the second
/// door on your left".
///
/// **Offline-first on reads.** Indoors is where this app is used and where a
/// connection is least reliable, so a plan fetched once is served from cache
/// when the network is not there. A traced plan is exactly the kind of data
/// that suits it: it changes when somebody retraces a floor, which is rarely,
/// and a slightly stale floor plan is enormously better than none. Same
/// treatment `tracedPlanOf` gets, for the same reason.
class SupabaseRoomPlanRepository
    with RepositoryMixin
    implements RoomPlanRepository {
  const SupabaseRoomPlanRepository(this._client);

  final SupabaseClient _client;

  /// The device's own copy, which is both the offline cache and the holding
  /// place for a floor traced while offline.
  ///
  /// Deliberately the real repository rather than [runOfflineFirstQuery]'s
  /// generic cache. The two wrote the *same key* in different shapes — this
  /// encoded `toJson()` as a map, [LocalRoomPlanRepository] encodes it as a
  /// JSON string — so a plan saved on the device decoded to null here and read
  /// back as "nobody has traced this floor". One store, one shape, no chance
  /// of the two disagreeing.
  static const RoomPlanRepository _local = LocalRoomPlanRepository();

  @override
  Future<RoomPlan?> planFor(String buildingId, String floorId) async {
    try {
      final rows = await runOperation('room_plan_for', () async {
        return await _client
            .from('room_plans')
            .select('plan')
            .eq('building_id', buildingId)
            .eq('floor_id', floorId)
            .limit(1);
      });
      final plan = rows.isEmpty ? null : _decode(rows.first['plan']);
      if (plan != null) {
        // Keep the device copy current, so the next read works with no signal.
        await _cacheLocally(plan);
        return plan;
      }
      // The server has no plan for this floor. That is not the same as there
      // being none: a floor traced while offline lives here and nowhere else
      // until it publishes.
      return _local.planFor(buildingId, floorId);
    } catch (error) {
      AppLogger.warn('Room plan for $buildingId/$floorId from device: $error');
      return _local.planFor(buildingId, floorId);
    }
  }

  @override
  Future<List<RoomPlan>> plansOf(String buildingId) async {
    final List<RoomPlan> local;
    try {
      local = await _local.plansOf(buildingId);
    } catch (_) {
      return _remotePlansOf(buildingId);
    }

    final List<RoomPlan> remote;
    try {
      remote = await _remotePlansOf(buildingId);
    } catch (error) {
      AppLogger.warn('Room plans for $buildingId from device: $error');
      return local;
    }

    for (final plan in remote) {
      await _cacheLocally(plan);
    }

    // Server wins per floor — it is the shared truth — but a floor only this
    // device has traced still belongs in the list, or an unpublished floor
    // silently vanishes from the building the moment the network comes back.
    final floors = {for (final plan in remote) plan.floorId};
    return [
      ...remote,
      for (final plan in local)
        if (!floors.contains(plan.floorId)) plan,
    ];
  }

  /// Device-local, deliberately — even with a server behind it.
  ///
  /// The Maps tab lists the floors this phone can walk right now. Every plan
  /// the server has ever accepted is a different list, it is unbounded, and
  /// fetching it is the one thing that cannot work in the case the tab is for.
  /// A floor arrives here by being traced or by being opened once, both of
  /// which cache it locally.
  @override
  Future<List<RoomPlan>> allPlans() => _local.allPlans();

  Future<List<RoomPlan>> _remotePlansOf(String buildingId) {
    return runOperation('room_plans_of', () async {
      final rows = await _client
          .from('room_plans')
          .select('plan')
          .eq('building_id', buildingId);
      return [
        for (final row in rows)
          if (_decode(row['plan']) case final plan?) plan,
      ];
    });
  }

  // Drafts stay on the device even when there is a server. Half a traced floor
  // is not something anybody else should receive, and the whole point of the
  // draft is that it survives without a round trip.
  @override
  Future<void> saveDraft(RoomPlan plan) => _local.saveDraft(plan);

  @override
  Future<RoomPlan?> draftFor(String buildingId, String floorId) =>
      _local.draftFor(buildingId, floorId);

  @override
  Future<void> clearDraft(String buildingId, String floorId) =>
      _local.clearDraft(buildingId, floorId);

  /// Mirroring the server locally must never fail a read that already
  /// succeeded — the caller has the plan in hand either way.
  Future<void> _cacheLocally(RoomPlan plan) async {
    try {
      await _local.save(plan);
    } catch (error) {
      AppLogger.warn('Could not cache room plan on device: $error');
    }
  }

  @override
  Future<void> save(RoomPlan plan) async {
    if (plan.drawableRooms.isEmpty) {
      throw const OperationFailure('Trace at least one room before saving');
    }

    // Local first, unconditionally, before anything can go over the wire.
    //
    // A traced floor is ~fifteen minutes of somebody standing in front of a
    // board, and it used to live only in the Bloc until a round trip
    // succeeded — so a missing RPC, an expired session or a dead campus
    // connection took the whole trace with the process. Nothing about that
    // work is server-owned; it is the contributor's until they choose to
    // share it. Sharing is what needs the network, not keeping.
    var keptOnDevice = true;
    try {
      await _local.save(plan);
    } catch (error, stack) {
      // A device that cannot hold the plan is a reason to try *harder* to
      // publish it, not a reason to stop before trying: the upload is now the
      // only thing standing between the contributor and a lost floor.
      keptOnDevice = false;
      AppLogger.error('Room plan could not be kept on device', error, stack);
    }

    // Then publish. One RPC rather than a bare upsert, matching
    // `save_traced_plan`: the function validates the payload server-side and
    // is the single place the replace-this-floor semantics live, so a second
    // client cannot invent different ones.
    try {
      await runOperation('save_room_plan', () async {
        await _client.rpc<void>(
          'save_room_plan',
          params: {'p_plan': plan.toJson()},
        );
      });
    } on OperationFailure {
      // Nothing kept it, so say what actually went wrong — "saved on this
      // device" would be false, and it is the sentence that decides whether
      // somebody walks away from twenty minutes of work.
      if (!keptOnDevice) rethrow;

      // Deliberately still an error, but a different one: the trace is safe,
      // and telling somebody "saved" when nobody else can see it yet would be
      // a lie they only discover when they look for it on another phone.
      throw const OperationFailure(
        'Saved on this device, but not shared yet — check your connection '
        'and save again to publish it.',
      );
    }
  }

  @override
  Future<void> delete(String buildingId, String floorId) {
    return runOperation('delete_room_plan', () async {
      await _client
          .from('room_plans')
          .delete()
          .eq('building_id', buildingId)
          .eq('floor_id', floorId);
    });
  }

  /// A row that will not decode is treated as absent rather than as a crash.
  ///
  /// Schema drift after an app update is the realistic cause. The cost of
  /// returning null is being asked to retrace a floor; the cost of throwing is
  /// a building that cannot be opened at all.
  static RoomPlan? _decode(Object? stored) {
    if (stored is! Map) return null;
    try {
      return RoomPlan.fromJson(Map<String, dynamic>.from(stored));
    } catch (_) {
      return null;
    }
  }
}
