import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/landmark.dart';
import '../../core/models/route_draft.dart';
import '../../core/models/traced_plan.dart';
import '../../core/models/walk_route.dart';
import '../../data/repository_mixin.dart';
import 'route_repository.dart';

/// Supabase-backed landmarks and routes.
///
/// Reads are offline-first: once a building has been opened, its landmarks and
/// routes stay in Hive, so guidance keeps working in a corridor with no signal
/// — which is the normal case indoors, and the reason NFR-03 exists.
///
/// The database speaks snake_case; this class is the only place that knows how
/// those columns map onto the models.
class SupabaseRouteRepository with RepositoryMixin implements RouteRepository {
  SupabaseRouteRepository(this._client);

  final SupabaseClient _client;

  static const _landmarkColumns =
      'id, building_id, floor_id, kind, label_text, aliases, '
      'display_name, room_id';

  static const _routeColumns =
      'id, building_id, start_landmark_id, destination_room_id, '
      'total_distance_m, verified_count, '
      'route_steps(seq, from_landmark_id, to_landmark_id, instruction, '
      'distance_m, steps_recorded, turn_deg)';

  Landmark _landmarkFrom(Map<String, dynamic> row) => Landmark(
        id: row['id'] as String,
        buildingId: row['building_id'] as String,
        floorId: row['floor_id'] as String,
        kind: LandmarkKind.fromName(row['kind'] as String?),
        labelText: row['label_text'] as String,
        displayName: row['display_name'] as String,
        aliases:
            (row['aliases'] as List<dynamic>? ?? const []).cast<String>(),
        roomId: row['room_id'] as String?,
      );

  WalkRoute _routeFrom(Map<String, dynamic> row) {
    final steps = (row['route_steps'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (s) => RouteStep(
            seq: (s['seq'] as num).toInt(),
            fromLandmarkId: s['from_landmark_id'] as String,
            toLandmarkId: s['to_landmark_id'] as String,
            instruction: s['instruction'] as String,
            distanceM: (s['distance_m'] as num).toDouble(),
            turnDeg: (s['turn_deg'] as num?)?.toInt() ?? 0,
            stepsRecorded: (s['steps_recorded'] as num?)?.toInt(),
          ),
        )
        .toList()
      // PostgREST does not guarantee embedded row order.
      ..sort((a, b) => a.seq.compareTo(b.seq));

    return WalkRoute(
      id: row['id'] as String,
      buildingId: row['building_id'] as String,
      startLandmarkId: row['start_landmark_id'] as String,
      destinationRoomId: row['destination_room_id'] as String,
      totalDistanceM: (row['total_distance_m'] as num?)?.toDouble() ?? 0,
      verifiedCount: (row['verified_count'] as num?)?.toInt() ?? 0,
      steps: steps,
    );
  }

  @override
  Future<List<Landmark>> landmarksOf(String buildingId) {
    return runOfflineFirstQuery(
      'landmarks:$buildingId',
      () async {
        final rows = await _client
            .from('landmarks')
            .select(_landmarkColumns)
            .eq('building_id', buildingId);
        return rows.map(_landmarkFrom).toList();
      },
      encode: (list) => list.map((l) => l.toJson()).toList(),
      decode: (cached) => (cached as List)
          .map((e) => Landmark.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  @override
  Future<List<WalkRoute>> routesOf(String buildingId) {
    return runOfflineFirstQuery(
      'routes:$buildingId',
      () async {
        final rows = await _client
            .from('routes')
            .select(_routeColumns)
            .eq('building_id', buildingId);
        return rows.map(_routeFrom).toList();
      },
      encode: (list) => list.map((r) => r.toJson()).toList(),
      decode: (cached) => (cached as List)
          .map((e) => WalkRoute.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  @override
  Future<WalkRoute?> routeTo(String buildingId, String roomId) async {
    // Served from the same cache as routesOf, so picking a destination works
    // offline once the building has been opened.
    final routes = await routesOf(buildingId);
    final matches =
        routes.where((r) => r.destinationRoomId == roomId).toList()
          ..sort((a, b) => b.verifiedCount.compareTo(a.verifiedCount));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<String> saveRoute(RouteDraft draft) {
    return runOperation('save_route', () async {
      if (draft.steps.isEmpty) {
        throw const OperationFailure('Record at least one leg before saving');
      }
      // One RPC, one transaction: landmarks and their legs are written
      // together or not at all. A half-written route would draw a broken map.
      final id = await _client.rpc<String>(
        'save_route',
        params: {'p_route': draft.toRpcPayload()},
      );
      return id;
    });
  }

  @override
  Future<TracedPlan?> tracedPlanOf(String buildingId) {
    return runOfflineFirstQuery(
      'traced_plan:$buildingId',
      () async {
        final rows = await _client
            .from('traced_plans')
            .select('plan')
            .eq('building_id', buildingId)
            .limit(1);
        if (rows.isEmpty) return null;
        return TracedPlan.fromJson(
          Map<String, dynamic>.from(rows.first['plan'] as Map),
        );
      },
      encode: (plan) => plan?.toJson(),
      decode: (cached) => cached == null
          ? null
          : TracedPlan.fromJson(Map<String, dynamic>.from(cached as Map)),
    );
  }

  @override
  Future<TracedPlan> saveTracedPlan(TracedPlan plan) {
    return runOperation('save_traced_plan', () async {
      if (plan.nodes.isEmpty) {
        throw const OperationFailure(
          'Place at least one landmark before saving',
        );
      }
      // One RPC, one transaction, for the same reason as save_route: the
      // landmarks and the plan that references them are written together, so a
      // dropped connection cannot leave a plan pointing at ids that were never
      // created. The function returns the plan with refs already resolved.
      final saved = await _client.rpc<Map<String, dynamic>>(
        'save_traced_plan',
        params: {'p_plan': plan.toJson()},
      );
      return TracedPlan.fromJson(Map<String, dynamic>.from(saved));
    });
  }
}
