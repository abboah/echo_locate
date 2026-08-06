import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/building.dart';
import '../../data/repository_mixin.dart';
import 'building_repository.dart';

/// Supabase-backed building index. Replaces [MockBuildingRepository] behind
/// the same interface when `AppConfig.hasSupabase` is true — no screen or
/// bloc changes.
///
/// Reads go through `buildings_view` and the RPCs defined in
/// `supabase/migrations/20260731090000_init_schema.sql`, which compute the
/// derived fields the cards render (floor count, mapper count, "updated
/// today", distance). The database returns snake_case; this class is the only
/// place that knows how those map onto the camelCase model.
///
/// Lists are cached to Hive network-first, so the Maps and Explore tabs still
/// render the last known index with no connection.
class SupabaseBuildingRepository
    with RepositoryMixin
    implements BuildingRepository {
  SupabaseBuildingRepository(this._client);

  final SupabaseClient _client;

  /// Columns of `buildings_view` that back the [Building] model.
  static const _buildingColumns =
      'id, name, area, category, glyph, mapped_percent, '
      'floors_count, mappers, updated_label, distance_km';

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const OperationFailure('Not signed in');
    return id;
  }

  Building _buildingFrom(Map<String, dynamic> row) => Building(
        id: row['id'] as String,
        name: row['name'] as String,
        area: row['area'] as String? ?? '',
        floorsCount: (row['floors_count'] as num?)?.toInt() ?? 0,
        mappers: (row['mappers'] as num?)?.toInt() ?? 0,
        mappedPercent: (row['mapped_percent'] as num?)?.toInt() ?? 0,
        distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
        category: row['category'] as String? ?? 'campus',
        glyph: row['glyph'] as String? ?? 'building',
        updatedLabel: row['updated_label'] as String? ?? 'updated recently',
      );

  List<Building> _buildingsFrom(List<dynamic> rows) => rows
      .cast<Map<String, dynamic>>()
      .map(_buildingFrom)
      .toList(growable: false);

  // Hive can only store primitives/lists/maps, so buildings round-trip as
  // their JSON form.
  Object? _encodeList(List<Building> list) =>
      list.map((b) => b.toJson()).toList();

  List<Building> _decodeList(Object? cached) => (cached as List)
      .map((e) => Building.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  @override
  Future<List<Building>> recentlyMapped() {
    return runOfflineFirstQuery(
      'buildings:recent',
      () async {
        final rows = await _client.rpc<List<dynamic>>(
          'recently_mapped_buildings',
          params: {'p_limit': 4},
        );
        return _buildingsFrom(rows);
      },
      encode: _encodeList,
      decode: _decodeList,
    );
  }

  @override
  Future<List<Building>> nearby({
    String category = 'all',
    String query = '',
  }) async {
    final trimmed = query.trim();
    // Filtering happens in SQL (see nearby_buildings), which also sorts by
    // distance. Only the unfiltered list is worth caching for offline use.
    Future<List<Building>> fetch() async {
      final rows = await _client.rpc<List<dynamic>>(
        'nearby_buildings',
        params: {'p_category': category, 'p_query': trimmed},
      );
      return _buildingsFrom(rows);
    }

    if (category == 'all' && trimmed.isEmpty) {
      return runOfflineFirstQuery(
        'buildings:all',
        fetch,
        encode: _encodeList,
        decode: _decodeList,
      );
    }
    return runOperation('buildings_nearby', fetch);
  }

  @override
  Future<Building> byId(String id) {
    return runOperation('building_by_id', () async {
      final row = await _client
          .from('buildings_view')
          .select(_buildingColumns)
          .eq('id', id)
          .maybeSingle();
      if (row == null) throw const OperationFailure('Building not found');
      return _buildingFrom(row);
    });
  }

  @override
  Future<List<BuildingFloor>> floorsOf(String buildingId) {
    return runOfflineFirstQuery(
      'floors:$buildingId',
      () async {
        final rows = await _client
            .from('floors')
            .select('id, label, ordinal, rooms(id, name, kind, distance_m)')
            .eq('building_id', buildingId)
            .order('ordinal');

        return rows.map((row) {
          final rooms = (row['rooms'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>()
              .map((r) => Room(
                    id: r['id'] as String,
                    name: r['name'] as String,
                    distanceM: (r['distance_m'] as num?)?.toInt() ?? 0,
                    kind: r['kind'] as String? ?? 'room',
                  ))
              .toList()
            ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
          return BuildingFloor(
            id: row['id'] as String,
            label: row['label'] as String,
            rooms: rooms,
          );
        }).toList();
      },
      encode: (floors) => floors.map((f) => f.toJson()).toList(),
      decode: (cached) => (cached as List)
          .map((e) => BuildingFloor.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  @override
  Future<List<Building>> savedMaps() {
    return runOfflineFirstQuery(
      'buildings:saved',
      () async {
        // saved_maps points at `buildings`, not the view, so PostgREST can't
        // embed the computed columns — fetch the ids, then the rows.
        final saved = await _client
            .from('saved_maps')
            .select('building_id')
            .eq('user_id', _userId)
            .order('saved_at', ascending: false);

        final ids =
            saved.map((r) => r['building_id'] as String).toList(growable: false);
        if (ids.isEmpty) return <Building>[];

        final rows = await _client
            .from('buildings_view')
            .select(_buildingColumns)
            .inFilter('id', ids);
        return _buildingsFrom(rows);
      },
      encode: _encodeList,
      decode: _decodeList,
    );
  }

  @override
  Future<bool> isSaved(String buildingId) {
    return runOperation('building_is_saved', () async {
      final row = await _client
          .from('saved_maps')
          .select('building_id')
          .eq('user_id', _userId)
          .eq('building_id', buildingId)
          .maybeSingle();
      return row != null;
    });
  }

  @override
  Future<bool> setSaved(String buildingId, bool saved) {
    return runOperation('building_set_saved', () async {
      if (saved) {
        await _client.from('saved_maps').upsert({
          'user_id': _userId,
          'building_id': buildingId,
        });
      } else {
        await _client
            .from('saved_maps')
            .delete()
            .eq('user_id', _userId)
            .eq('building_id', buildingId);
      }
      // No cache to invalidate: savedMaps() is network-first and only falls
      // back to Hive when the fetch itself fails.
      return saved;
    });
  }
}
