import 'package:hive_ce_flutter/hive_ce_flutter.dart';
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
    double? latitude,
    double? longitude,
  }) async {
    final trimmed = query.trim();
    // Filtering happens in SQL (see nearby_buildings), which also sorts by
    // distance. Only the unfiltered list is worth caching for offline use.
    Future<List<Building>> fetch() async {
      final rows = await _client.rpc<List<dynamic>>(
        'nearby_buildings',
        params: {
          'p_category': category,
          'p_query': trimmed,
          // The function has taken these since the first migration and the
          // client never sent them, so `coalesce(p_lat, o.lat)` fell through
          // to the server's default origin every time: every user, wherever
          // they stood, saw one fixed set of distances. Null is still allowed
          // and still means that — it is now a refused permission rather than
          // an omission.
          'p_lat': latitude,
          'p_lng': longitude,
        },
      );
      return _buildingsFrom(rows);
    }

    // Only the unpositioned, unfiltered list is cached. A list ordered around
    // where somebody was standing an hour ago is worse than no list: it looks
    // current and is not.
    if (category == 'all' && trimmed.isEmpty && latitude == null) {
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
  Future<Building> rename(String id, {required String name, String? area}) {
    return runOperation('building_rename', () async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const OperationFailure('A building needs a name.');
      }

      // The **id is not regenerated**. It is a slug of whatever the building
      // was first called, and it is the foreign key every floor, traced plan,
      // landmark and saved bookmark hangs off — re-slugging on rename would
      // orphan all of them silently. A name that no longer matches its slug is
      // cosmetic; a floor plan pointing at a building that no longer exists is
      // not.
      //
      // **Through an RPC, not a bare update.** This was
      // `update({name}).eq('id', id)`, and when the "buildings editable by
      // contributors" policy filtered the row away PostgREST returned success
      // having changed nothing — so a rename the user was not allowed to make
      // was indistinguishable from one that worked. The screen said "Your name
      // is now …" and the building kept its old one. `rename_building` raises
      // instead, and the message says who may rename it.
      await _client.rpc<void>(
        'rename_building',
        params: {
          'p_id': id,
          'p_name': trimmed,
          'p_area': area?.trim().isEmpty ?? true ? null : area!.trim(),
        },
      );
      RepositoryMixin.clearEphemeralCache();
      return byId(id);
    });
  }

  @override
  Future<void> delete(String id) {
    return runOperation('building_delete', () async {
      if (_client.auth.currentUser == null) {
        throw const OperationFailure('Not signed in');
      }
      // Same reasoning as the rename: a `delete` filtered away by RLS reports
      // success and removes nothing. The function decides — creator only, and
      // only while nobody else has traced a floor here — and raises with a
      // sentence the screen can show verbatim.
      await _client.rpc<void>('delete_own_building', params: {'p_id': id});
      RepositoryMixin.clearEphemeralCache();
      // The building list is cached in Hive for offline use, and it still has
      // the row that has just gone.
      await _forgetCachedList();
    });
  }

  /// Drops the persisted `buildings:all` list.
  ///
  /// `runOfflineFirstQuery` is network-first, so this only matters when the
  /// next read fails — but that is exactly when a deleted building would come
  /// back from the cache looking real.
  Future<void> _forgetCachedList() async {
    try {
      await Hive.box(repoCacheBoxName).delete('buildings:all');
    } catch (_) {
      // A cache that cannot be cleared is not worth failing a delete over.
    }
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
          final rooms =
              (row['rooms'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>()
                  .map(
                    (r) => Room(
                      id: r['id'] as String,
                      name: r['name'] as String,
                      distanceM: (r['distance_m'] as num?)?.toInt() ?? 0,
                      kind: r['kind'] as String? ?? 'room',
                    ),
                  )
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
          .map(
            (e) => BuildingFloor.fromJson(Map<String, dynamic>.from(e as Map)),
          )
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

        final ids = saved
            .map((r) => r['building_id'] as String)
            .toList(growable: false);
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

  @override
  Future<Building> create({
    required String name,
    required String area,
    String category = 'campus',
    int floors = 1,
  }) {
    return runOperation('building_create', () async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const OperationFailure('Give the building a name');
      }

      // `buildings.id` is a human-readable slug rather than a uuid, so it is
      // generated here. A collision is somebody else's building, not this one:
      // suffix rather than upsert, or a contributor adding "Great Hall" would
      // silently start editing the Great Hall that already exists.
      final base = slugify(trimmed);
      var id = base;
      for (var n = 2; n < 50; n++) {
        final clash = await _client
            .from('buildings')
            .select('id')
            .eq('id', id)
            .maybeSingle();
        if (clash == null) break;
        id = '$base-$n';
      }

      await _client.from('buildings').insert({
        'id': id,
        'name': trimmed,
        'area': area.trim(),
        'category': category,
        'glyph': 'building',
        'mapped_percent': 0,
        // RLS requires this to be the caller: "buildings insertable by
        // signed-in users" checks created_by = auth.uid().
        'created_by': _userId,
      });

      // Whoever adds a building is its first contributor, which is also what
      // grants them the right to write its floors and, later, its traced plan.
      await _client.from('building_contributors').upsert({
        'building_id': id,
        'user_id': _userId,
      });

      // Floors up front, and empty: a traced plan's nodes reference a real
      // `floors.id` uuid, so a building with no floor rows cannot be traced at
      // all. Rooms are deliberately not invented — the contributor is about to
      // record them.
      await _client.from('floors').insert([
        for (var i = 0; i < floors; i++)
          {'building_id': id, 'label': i == 0 ? 'G' : '$i', 'ordinal': i},
      ]);

      // Explore and Home read cached lists, so a new building would not appear
      // until the next cold start without this.
      RepositoryMixin.clearEphemeralCache();

      final row = await _client
          .from('buildings_view')
          .select(_buildingColumns)
          .eq('id', id)
          .single();
      return _buildingFrom(row);
    });
  }
}
