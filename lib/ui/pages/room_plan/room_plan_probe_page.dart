import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../services/mapping/room_directions.dart';
import '../../../services/mapping/room_graph.dart';
import '../../widgets/room_plan_view.dart';

/// Makes the room-plan layer observable without a device that can capture one.
///
/// The floorplan spec's build order puts the ARCore bridge first and everything
/// else behind it. That ordering is wrong for this team: the test phone
/// (Infinix X657C) is not ARCore-certified — `requestInfo returned: -100` — so
/// gating the renderer, the router and the directions on native capture would
/// mean none of them could be run at all, on the only hardware available daily.
///
/// Everything downstream of capture is pure Dart, so it is exercised here
/// against a hand-built floor instead: pick a start and a destination, watch the
/// route draw, read the spoken instructions it generates. The same screen is the
/// fastest way to check a real captured plan later — swap the fixture for it.
///
/// A plain `StatefulWidget` rather than a Bloc, following `DepthProbePage`: this
/// is diagnostic surface, and the real screen will own its own Bloc against the
/// same services. Adding one here would mean writing a Bloc to delete.
class RoomPlanProbePage extends StatefulWidget {
  const RoomPlanProbePage({super.key});

  @override
  State<RoomPlanProbePage> createState() => _RoomPlanProbePageState();
}

class _RoomPlanProbePageState extends State<RoomPlanProbePage> {
  late final RoomPlan _plan = _sampleFloor();
  late final RoomNavGraph _graph = RoomNavGraph.build(_plan);

  String _fromId = 'lobby';
  String _toId = 'n3';

  RoomRoute? get _route => _graph.route(fromRoomId: _fromId, toRoomId: _toId);

  List<RoomInstruction> get _instructions {
    final route = _route;
    if (route == null) return const [];
    // Facing east down the corridor, which is how somebody comes in the door.
    return RoomDirections.forPlan(
      _plan,
    ).describe(_graph, route, initialHeading: const Offset(1, 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = _route;
    final rooms = _plan.drawableRooms.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Room plan probe'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: RoomPlanView(
              plan: _plan,
              route: route,
              highlightedRoomId: _fromId,
              onRoomTap: (id) => setState(() => _toId = id),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.all(AppDimens.space16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _roomPicker(
                        label: 'From',
                        value: _fromId,
                        rooms: rooms,
                        onChanged: (id) => setState(() => _fromId = id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _roomPicker(
                        label: 'To',
                        value: _toId,
                        rooms: rooms,
                        onChanged: (id) => setState(() => _toId = id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Above the instructions, not below them. Whether the ordinals
                // in those instructions can be trusted is the first thing a
                // reader needs to know, and a warning under a long list is a
                // warning nobody scrolls to.
                Text(
                  _plan.isRoutable
                      ? 'Corridor door count checks out — ordinals are safe to speak.'
                      : 'Corridor incomplete: ${_plan.incompleteCorridors} '
                            'door(s) untagged. Ordinals suppressed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _plan.isRoutable
                        ? theme.textTheme.bodySmall?.color
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(height: 12),
                if (route == null)
                  Text(
                    'No route on this floor.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.error,
                    ),
                  )
                else ...[
                  Text(
                    '${route.totalDistanceM.toStringAsFixed(1)} m · '
                    '${route.roomsPassed.length} rooms',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final instruction in _instructions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('· '),
                          Expanded(
                            child: Text(
                              instruction.text,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomPicker({
    required String label,
    required String value,
    required List<Room> rooms,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      for (final room in rooms)
        DropdownMenuItem(
          value: room.id,
          child: Text(room.displayName, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (id) {
      if (id != null) onChanged(id);
    },
  );
}

/// A wing with one corridor and rooms either side — the shape the spec's
/// wing-based capture (§8) produces, and the shape door counting is about.
RoomPlan _sampleFloor() {
  Room rect(
    String id,
    String code,
    RoomCategory category,
    double left,
    double right,
    double bottom,
    double top, [
    String? label,
  ]) => Room(
    id: id,
    floorId: 'gf',
    code: code,
    category: category,
    label: label,
    polygon: [
      RoomCorner(x: left, y: bottom),
      RoomCorner(x: right, y: bottom),
      RoomCorner(x: right, y: top),
      RoomCorner(x: left, y: top),
    ],
  );

  Opening door(String id, String a, String? b, double x, double y) => Opening(
    id: id,
    roomAId: a,
    roomBId: b,
    at: RoomCorner(x: x, y: y),
  );

  const openings = <Opening>[];

  final plan = RoomPlan(
    buildingId: 'knust-cs',
    floorId: 'gf',
    codePrefix: 'GF',
    // Hand-built in metres, so distances may be spoken. A plan traced off a
    // photograph leaves this null and the instructions drop their distances.
    metresPerUnit: 1,
    storedRooms: [
      rect('corridor', 'GF 0', RoomCategory.corridor, 0, 24, -1, 1),
      rect('lobby', 'GF 1', RoomCategory.commonRoom, -7, 0, -2.5, 2.5, 'Lobby'),
      rect('n1', 'GF 2', RoomCategory.office, 3, 6, 1, 6),
      rect(
        'n2',
        'GF 3',
        RoomCategory.office,
        8,
        11,
        1,
        6,
        'Digital Forensic Office',
      ),
      rect('n3', 'GF 4', RoomCategory.laboratory, 13, 18, 1, 7, 'Networks Lab'),
      rect('n4', 'GF 5', RoomCategory.staircase, 20, 23, 1, 4),
      rect('s1', 'GF 6', RoomCategory.lectureHall, 4, 10, -8, -1),
      rect('s2', 'GF 7', RoomCategory.washroom, 12, 14, -5, -1),
      rect('s3', 'GF 8', RoomCategory.library, 16, 22, -7, -1),
    ],
    storedOpenings: [
      ...openings,
      door('d-lobby', 'corridor', 'lobby', 0, 0),
      door('d-n1', 'corridor', 'n1', 4.5, 1),
      door('d-n2', 'corridor', 'n2', 9.5, 1),
      door('d-n3', 'corridor', 'n3', 15.5, 1),
      door('d-n4', 'corridor', 'n4', 21.5, 1),
      door('d-s1', 'corridor', 's1', 7, -1),
      door('d-s2', 'corridor', 's2', 13, -1),
      door('d-s3', 'corridor', 's3', 19, -1),
      door('d-exit', 'lobby', null, -7, 0),
    ],
  );

  // The count a mapper types after walking the corridor and counting doors by
  // eye. Correct here, so ordinals are spoken; change it and the probe shows
  // the guard suppressing them.
  return plan.copyWith(
    declaredDoorCounts: {'corridor': plan.openingsOn('corridor').length},
  );
}
