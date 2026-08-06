-- Seed: one hand-authored route, KNUST Library main entrance → Reading Hall.
--
-- Exists so Stream A (turtle layout, node snapping, A*, floor-plan painter)
-- has real input from hour one instead of waiting on Stream B's capture flow.
-- Distances and instructions are plausible placeholders, NOT surveyed — the
-- first genuine field capture should replace this route wholesale.
--
-- Deliberately crosses floors (ground → 2) so the stairs case is exercised by
-- the layout code from the start.
--
-- Idempotent: landmarks upsert on their natural key; the route is rebuilt.

do $$
declare
  v_building   constant text := 'knust-library';
  v_floor_g    uuid;
  v_floor_2    uuid;
  v_room       uuid;
  v_entrance   uuid;
  v_desk       uuid;
  v_stairs_g   uuid;
  v_landing_2  uuid;
  v_corridor_2 uuid;
  v_door       uuid;
  v_route      uuid;
begin
  select id into v_floor_g from public.floors
   where building_id = v_building and ordinal = 0;
  select id into v_floor_2 from public.floors
   where building_id = v_building and ordinal = 2;

  select r.id into v_room
    from public.rooms r
   where r.floor_id = v_floor_2 and r.name = 'Reading Hall';

  if v_floor_g is null or v_floor_2 is null or v_room is null then
    raise notice 'seed_library_route: KNUST Library floors/rooms missing — skipped';
    return;
  end if;

  -- Landmarks -------------------------------------------------------------
  insert into public.landmarks
    (building_id, floor_id, kind, label_text, aliases, display_name, room_id)
  values
    (v_building, v_floor_g, 'entrance', 'KNUST LIBRARY', '{}',        'Main entrance',        null),
    (v_building, v_floor_g, 'junction', 'HELP DESK',     '{"HELPDESK"}', 'Help desk',         null),
    (v_building, v_floor_g, 'stairs',   'STAIRS',        '{"STAIRWAY"}', 'Ground floor stairwell', null),
    (v_building, v_floor_2, 'stairs',   '2',             '{"FLOOR 2","2ND"}', 'Floor 2 landing', null),
    (v_building, v_floor_2, 'sign',     'ROOMS 201-210', '{"ROOMS 201 - 210","201-210"}', 'Floor 2 directory board', null),
    (v_building, v_floor_2, 'door',     'READING HALL',  '{"READINGHALL"}', 'Reading Hall door', v_room)
  on conflict (building_id, floor_id, display_name) do update
    set label_text = excluded.label_text,
        kind       = excluded.kind,
        aliases    = excluded.aliases,
        room_id    = coalesce(excluded.room_id, public.landmarks.room_id);

  select id into v_entrance  from public.landmarks
   where building_id = v_building and display_name = 'Main entrance';
  select id into v_desk      from public.landmarks
   where building_id = v_building and display_name = 'Help desk';
  select id into v_stairs_g  from public.landmarks
   where building_id = v_building and display_name = 'Ground floor stairwell';
  select id into v_landing_2 from public.landmarks
   where building_id = v_building and display_name = 'Floor 2 landing';
  select id into v_corridor_2 from public.landmarks
   where building_id = v_building and display_name = 'Floor 2 directory board';
  select id into v_door      from public.landmarks
   where building_id = v_building and display_name = 'Reading Hall door';

  -- Route -----------------------------------------------------------------
  delete from public.routes
   where building_id = v_building
     and destination_room_id = v_room
     and created_by is null;   -- only ever removes the seed, never a real capture

  insert into public.routes
    (building_id, start_landmark_id, destination_room_id, total_distance_m)
  values (v_building, v_entrance, v_room, 53)
  returning id into v_route;

  insert into public.route_steps
    (route_id, seq, from_landmark_id, to_landmark_id, instruction,
     distance_m, steps_recorded, turn_deg)
  values
    (v_route, 1, v_entrance,  v_desk,      'Straight ahead, past the entrance desk',              12, 16, 0),
    (v_route, 2, v_desk,      v_stairs_g,  'Turn right; the stairwell is at the end of the corridor', 18, 24, 90),
    (v_route, 3, v_stairs_g,  v_landing_2, 'Take the stairs up two flights to floor 2',            8, 11, 0),
    (v_route, 4, v_landing_2, v_corridor_2,'Turn left along the main corridor to the directory board', 9, 12, -90),
    (v_route, 5, v_corridor_2,v_door,      'Straight on; the Reading Hall is the second door on your right', 6,  8, 0);
end $$;
