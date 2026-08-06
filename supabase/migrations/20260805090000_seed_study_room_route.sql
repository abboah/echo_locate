-- Seed: a second hand-authored route, KNUST Library main entrance → Study
-- Room 2B, sharing its first four legs with the Reading Hall route.
--
-- Exists for one reason: two routes that overlap are what A* needs to find a
-- path nobody walked (spec §6 A4). With only the Reading Hall route in the
-- database, every query is answerable by replaying a recording, and the
-- claim this project defends is never exercised.
--
-- The two routes diverge at the floor 2 directory board — Reading Hall
-- straight on, Study Room 2B to the right — so `planBetweenRooms` must splice
-- the tail of one onto the reversed tail of the other, recomputing the turn at
-- the board and rewording the leg it walks backwards.
--
-- Distances and instructions are plausible placeholders, NOT surveyed. The
-- first genuine field capture should replace both routes wholesale.
--
-- Idempotent: the landmark upserts on its natural key; the route is rebuilt.

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
   where r.floor_id = v_floor_2 and r.name = 'Study Room 2B';

  if v_floor_g is null or v_floor_2 is null or v_room is null then
    raise notice 'seed_study_room_route: KNUST Library floors/rooms missing — skipped';
    return;
  end if;

  -- The only new landmark: the rest are shared with the Reading Hall route,
  -- which is what makes the two graphs merge into one.
  insert into public.landmarks
    (building_id, floor_id, kind, label_text, aliases, display_name, room_id)
  values
    (v_building, v_floor_2, 'door', '2B', '{"28","2 B"}', 'Study Room 2B door', v_room)
  on conflict (building_id, floor_id, display_name) do update
    set label_text = excluded.label_text,
        kind       = excluded.kind,
        aliases    = excluded.aliases,
        room_id    = coalesce(excluded.room_id, public.landmarks.room_id);

  select id into v_entrance   from public.landmarks
   where building_id = v_building and display_name = 'Main entrance';
  select id into v_desk       from public.landmarks
   where building_id = v_building and display_name = 'Help desk';
  select id into v_stairs_g   from public.landmarks
   where building_id = v_building and display_name = 'Ground floor stairwell';
  select id into v_landing_2  from public.landmarks
   where building_id = v_building and display_name = 'Floor 2 landing';
  select id into v_corridor_2 from public.landmarks
   where building_id = v_building and display_name = 'Floor 2 directory board';
  select id into v_door       from public.landmarks
   where building_id = v_building and display_name = 'Study Room 2B door';

  if v_entrance is null or v_corridor_2 is null then
    raise notice 'seed_study_room_route: Reading Hall seed has not run — skipped';
    return;
  end if;

  delete from public.routes
   where building_id = v_building
     and destination_room_id = v_room
     and created_by is null;   -- only ever removes the seed, never a real capture

  insert into public.routes
    (building_id, start_landmark_id, destination_room_id, total_distance_m)
  values (v_building, v_entrance, v_room, 54)
  returning id into v_route;

  insert into public.route_steps
    (route_id, seq, from_landmark_id, to_landmark_id, instruction,
     distance_m, steps_recorded, turn_deg)
  values
    (v_route, 1, v_entrance,   v_desk,       'Straight ahead, past the entrance desk',                   12, 16,  0),
    (v_route, 2, v_desk,       v_stairs_g,   'Turn right; the stairwell is at the end of the corridor',  18, 25, 90),
    (v_route, 3, v_stairs_g,   v_landing_2,  'Take the stairs up two flights to floor 2',                 8, 11,  0),
    (v_route, 4, v_landing_2,  v_corridor_2, 'Turn left along the main corridor to the directory board',  9, 12, -90),
    (v_route, 5, v_corridor_2, v_door,       'Turn right; Study Room 2B is the first door on your left',  7,  9, 90);
end $$;
