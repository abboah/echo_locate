-- Landmark navigation: the data behind sign-anchored wayfinding.
--
-- A contributor walks a building once. At each decision point they photograph
-- a sign (OCR proposes the text) and confirm it as a LANDMARK; between
-- landmarks the phone counts steps, which become a leg (ROUTE_STEP) with a
-- spoken instruction. The chain from an entrance to a room is a ROUTE.
--
-- Two things are derived from this, not stored: the 2D floor schematic (walk
-- each route as a turtle — rotate by turn_deg, advance distance_m) and the
-- navigation graph A* runs over (nodes = landmarks, edges = legs).
--
-- See docs/landmark-navigation-spec.md.

-- ---------------------------------------------------------------------------
-- landmarks — something the camera can recognise and a user can stand at
-- ---------------------------------------------------------------------------
create table public.landmarks (
  id            uuid primary key default gen_random_uuid(),
  building_id   text not null references public.buildings (id) on delete cascade,
  floor_id      uuid not null references public.floors (id) on delete cascade,
  kind          text not null
                  check (kind in ('entrance', 'junction', 'stairs', 'lift', 'door', 'sign')),
  -- What OCR must match, normalised (upper, single-spaced): '204'.
  label_text    text not null,
  -- Misreads observed in the field: '2O4', '2 04'. The matcher also allows a
  -- Levenshtein distance of 1, so this is for systematic errors only.
  aliases       text[] not null default '{}',
  display_name  text not null,
  -- Set when the landmark IS a room's door, which is how a route ends.
  room_id       uuid references public.rooms (id) on delete set null,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  -- Natural key: lets the capture flow and the seed upsert instead of
  -- duplicating a landmark every time someone re-walks a route.
  unique (building_id, floor_id, display_name)
);

create index landmarks_building_idx on public.landmarks (building_id);
create index landmarks_label_idx on public.landmarks (building_id, label_text);

-- ---------------------------------------------------------------------------
-- routes — one recorded walk, start point to destination room
-- ---------------------------------------------------------------------------
create table public.routes (
  id                  uuid primary key default gen_random_uuid(),
  building_id         text not null references public.buildings (id) on delete cascade,
  start_landmark_id   uuid not null references public.landmarks (id) on delete cascade,
  destination_room_id uuid not null references public.rooms (id) on delete cascade,
  total_distance_m    numeric not null default 0,
  -- Incremented when another user completes the route successfully; a crude
  -- quality signal for choosing between competing recordings.
  verified_count      int not null default 0,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now()
);

create index routes_building_idx on public.routes (building_id);
create index routes_destination_idx on public.routes (destination_room_id);

-- ---------------------------------------------------------------------------
-- route_steps — one leg, landmark to landmark
-- ---------------------------------------------------------------------------
create table public.route_steps (
  route_id         uuid not null references public.routes (id) on delete cascade,
  seq              int not null,
  from_landmark_id uuid not null references public.landmarks (id) on delete cascade,
  to_landmark_id   uuid not null references public.landmarks (id) on delete cascade,
  instruction      text not null,
  -- Canonical distance. NEVER store the contributor's step count as the
  -- distance: a 78cm stride and a 65cm stride do not share a step count, so
  -- metres is the only value that transfers between people.
  distance_m       numeric not null check (distance_m >= 0),
  -- The contributor's raw count, kept as evidence for the evaluation chapter.
  steps_recorded   int,
  -- Turn taken at the START of this leg. Tapped by the contributor, not
  -- sensed: 0 straight, -90 left, +90 right, -135/+135 sharp. A compass would
  -- add indoor magnetic error for no gain.
  turn_deg         int not null default 0
                     check (turn_deg in (-135, -90, 0, 90, 135)),
  primary key (route_id, seq)
);

-- ---------------------------------------------------------------------------
-- Per-user stride, for converting stored metres into this user's steps
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column stride_length_m numeric check (stride_length_m > 0);

comment on column public.profiles.stride_length_m is
  'Calibrated stride in metres (walk a measured 10m). Falls back to '
  '0.415 * height when absent.';

-- ---------------------------------------------------------------------------
-- save_route — atomic capture upload
--
-- PostgREST cannot span statements in one transaction, and a half-written
-- route (landmarks but no legs) is corrupt data that the map would silently
-- mis-draw. So the whole upload is one function call.
--
-- Payload:
-- {
--   "building_id": "knust-library",
--   "destination_room_id": "<uuid>",
--   "landmarks": [ { "ref": "L1", "floor_id": "<uuid>", "kind": "entrance",
--                    "label_text": "KNUST LIBRARY", "display_name": "Main entrance",
--                    "aliases": [], "room_id": null } ],
--   "steps": [ { "seq": 1, "from": "L1", "to": "L2", "instruction": "...",
--                "distance_m": 12.0, "steps_recorded": 16, "turn_deg": 0 } ]
-- }
--
-- `ref` is a client-side label; this function maps refs to real uuids so the
-- client never has to invent them.
-- ---------------------------------------------------------------------------
create or replace function public.save_route(p_route jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public as $$
declare
  v_building   text := p_route ->> 'building_id';
  v_room       uuid := (p_route ->> 'destination_room_id')::uuid;
  v_refs       jsonb := '{}'::jsonb;   -- ref -> landmark uuid
  v_landmark   jsonb;
  v_step       jsonb;
  v_id         uuid;
  v_route_id   uuid;
  v_total      numeric := 0;
  v_start      uuid;
begin
  if v_building is null or v_room is null then
    raise exception 'save_route: building_id and destination_room_id are required';
  end if;

  -- Recording a route makes you a contributor to the building. This is not
  -- bookkeeping: `can_edit_building` gates every write below, and a seeded
  -- building has no contributors, so without this the first person to map it
  -- would be refused by RLS.
  insert into public.building_contributors (building_id, user_id)
  values (v_building, auth.uid())
  on conflict (building_id, user_id) do nothing;

  -- Landmarks first: upsert on the natural key so re-walking a route reuses
  -- the landmarks already recorded rather than duplicating them.
  for v_landmark in select * from jsonb_array_elements(p_route -> 'landmarks')
  loop
    insert into public.landmarks
      (building_id, floor_id, kind, label_text, aliases, display_name, room_id, created_by)
    values (
      v_building,
      (v_landmark ->> 'floor_id')::uuid,
      v_landmark ->> 'kind',
      upper(trim(v_landmark ->> 'label_text')),
      coalesce(
        (select array_agg(value::text)
           from jsonb_array_elements_text(v_landmark -> 'aliases')),
        '{}'
      ),
      v_landmark ->> 'display_name',
      nullif(v_landmark ->> 'room_id', '')::uuid,
      auth.uid()
    )
    on conflict (building_id, floor_id, display_name) do update
      set label_text = excluded.label_text,
          kind       = excluded.kind,
          aliases    = excluded.aliases,
          room_id    = coalesce(excluded.room_id, public.landmarks.room_id)
    returning id into v_id;

    v_refs := v_refs || jsonb_build_object(v_landmark ->> 'ref', v_id::text);
  end loop;

  select sum((value ->> 'distance_m')::numeric)
    into v_total
    from jsonb_array_elements(p_route -> 'steps') as value;

  select (v_refs ->> (value ->> 'from'))::uuid
    into v_start
    from jsonb_array_elements(p_route -> 'steps') as value
   order by (value ->> 'seq')::int
   limit 1;

  insert into public.routes
    (building_id, start_landmark_id, destination_room_id, total_distance_m, created_by)
  values (v_building, v_start, v_room, coalesce(v_total, 0), auth.uid())
  returning id into v_route_id;

  for v_step in select * from jsonb_array_elements(p_route -> 'steps')
  loop
    insert into public.route_steps
      (route_id, seq, from_landmark_id, to_landmark_id,
       instruction, distance_m, steps_recorded, turn_deg)
    values (
      v_route_id,
      (v_step ->> 'seq')::int,
      (v_refs ->> (v_step ->> 'from'))::uuid,
      (v_refs ->> (v_step ->> 'to'))::uuid,
      v_step ->> 'instruction',
      (v_step ->> 'distance_m')::numeric,
      nullif(v_step ->> 'steps_recorded', '')::int,
      coalesce((v_step ->> 'turn_deg')::int, 0)
    );
  end loop;

  return v_route_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS — same shape as the rest of the schema: the index is readable by any
-- signed-in user, writable by the building's contributors.
-- ---------------------------------------------------------------------------
alter table public.landmarks   enable row level security;
alter table public.routes      enable row level security;
alter table public.route_steps enable row level security;

create policy "landmarks readable by signed-in users"
  on public.landmarks for select to authenticated using (true);
create policy "landmarks writable by contributors"
  on public.landmarks for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

create policy "routes readable by signed-in users"
  on public.routes for select to authenticated using (true);
create policy "routes writable by contributors"
  on public.routes for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

create policy "route steps readable by signed-in users"
  on public.route_steps for select to authenticated using (true);
create policy "route steps writable by contributors"
  on public.route_steps for all to authenticated
  using (
    exists (
      select 1 from public.routes r
      where r.id = route_steps.route_id and public.can_edit_building(r.building_id)
    )
  )
  with check (
    exists (
      select 1 from public.routes r
      where r.id = route_steps.route_id and public.can_edit_building(r.building_id)
    )
  );
