-- EchoLocate v2 — complete database setup, in one file.
--
-- Paste the whole thing into the Supabase SQL editor and run it once.
--
-- This is a CONSOLIDATION of everything in supabase/migrations/, rewritten to
-- be idempotent: every table is `if not exists`, every policy and trigger is
-- dropped before it is recreated, every function is `create or replace`, and
-- the seeds upsert. Run it on an empty project or on one that is already
-- half-migrated — the result is the same either way, and re-running it is
-- always safe.
--
-- `supabase/migrations/` remains the source of truth for the CLI. This file is
-- for the SQL editor, where migrations have to be applied by hand.
--
-- The last statement returns a table of checks. READ IT. The seed blocks bail
-- out quietly if their prerequisites are missing, and in the SQL editor a
-- skipped seed looks identical to a successful one.

-- ===========================================================================
-- 1 · Core tables
-- ===========================================================================

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  email       text not null default '',
  created_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Contributor identity. Populated from auth.users metadata by handle_new_user().';

create table if not exists public.buildings (
  id              text primary key,          -- slug, e.g. 'knust-library'
  name            text not null,
  area            text not null,
  category        text not null default 'campus'
                    check (category in ('campus', 'hospital', 'mall', 'office', 'other')),
  glyph           text not null default 'building'
                    check (glyph in ('building', 'door', 'home', 'hall', 'book')),
  mapped_percent  int  not null default 0
                    check (mapped_percent between 0 and 100),
  lat             double precision,
  lng             double precision,
  -- Demo scaffolding: seeded buildings have no real contributor rows, so the
  -- cards would all read "0 mappers". Added to the live count in buildings_view.
  seed_mappers    int  not null default 0,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists buildings_category_idx on public.buildings (category);

create table if not exists public.floors (
  id           uuid primary key default gen_random_uuid(),
  building_id  text not null references public.buildings (id) on delete cascade,
  label        text not null,   -- 'G', '1', '2' — shown on the floor chips
  ordinal      int  not null,   -- 0-based; sort key
  created_at   timestamptz not null default now(),
  unique (building_id, ordinal)
);

create index if not exists floors_building_idx on public.floors (building_id);

create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  floor_id    uuid not null references public.floors (id) on delete cascade,
  name        text not null,
  kind        text not null default 'room'
                check (kind in ('room', 'hall', 'desk')),
  distance_m  int  not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists rooms_floor_idx on public.rooms (floor_id);

create table if not exists public.building_contributors (
  building_id   text not null references public.buildings (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  floors_mapped int not null default 0,
  rooms_mapped  int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (building_id, user_id)
);

create index if not exists building_contributors_user_idx
  on public.building_contributors (user_id);

create table if not exists public.saved_maps (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  building_id text not null references public.buildings (id) on delete cascade,
  saved_at    timestamptz not null default now(),
  primary key (user_id, building_id)
);

-- ===========================================================================
-- 2 · Landmark navigation tables
-- ===========================================================================

create table if not exists public.landmarks (
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

create index if not exists landmarks_building_idx on public.landmarks (building_id);
create index if not exists landmarks_label_idx
  on public.landmarks (building_id, label_text);

create table if not exists public.routes (
  id                  uuid primary key default gen_random_uuid(),
  building_id         text not null references public.buildings (id) on delete cascade,
  start_landmark_id   uuid not null references public.landmarks (id) on delete cascade,
  destination_room_id uuid not null references public.rooms (id) on delete cascade,
  total_distance_m    numeric not null default 0,
  verified_count      int not null default 0,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now()
);

create index if not exists routes_building_idx on public.routes (building_id);
create index if not exists routes_destination_idx
  on public.routes (destination_room_id);

create table if not exists public.route_steps (
  route_id         uuid not null references public.routes (id) on delete cascade,
  seq              int not null,
  from_landmark_id uuid not null references public.landmarks (id) on delete cascade,
  to_landmark_id   uuid not null references public.landmarks (id) on delete cascade,
  instruction      text not null,
  -- Canonical distance. NEVER store the contributor's step count as the
  -- distance: a 78cm stride and a 65cm stride do not share a step count, so
  -- metres is the only value that transfers between people.
  distance_m       numeric not null check (distance_m >= 0),
  -- Raw count, kept as evidence for the evaluation chapter.
  steps_recorded   int,
  -- Turn taken at the START of this leg, tapped not sensed.
  turn_deg         int not null default 0
                     check (turn_deg in (-135, -90, 0, 90, 135)),
  primary key (route_id, seq)
);

-- Per-user stride, for converting stored metres into this user's steps.
alter table public.profiles
  add column if not exists stride_length_m numeric;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_stride_length_m_check'
  ) then
    alter table public.profiles
      add constraint profiles_stride_length_m_check check (stride_length_m > 0);
  end if;
end $$;

comment on column public.profiles.stride_length_m is
  'Calibrated stride in metres (walk a measured 10m). Falls back to '
  '0.415 * height when absent.';

-- ===========================================================================
-- 3 · Helper functions
-- ===========================================================================

-- Great-circle distance in km. Plain trig rather than PostGIS: we only ever
-- need "how far is this building", not spatial indexing.
create or replace function public.haversine_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable parallel safe as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then 0::double precision
    else 6371 * 2 * asin(sqrt(
      pow(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) *
      pow(sin(radians(lng2 - lng1) / 2), 2)
    ))
  end;
$$;

-- The exact strings the cards render, so the client never formats dates.
create or replace function public.updated_label(ts timestamptz)
returns text language sql stable parallel safe as $$
  select case
    when ts >= date_trunc('day', now())                        then 'updated today'
    when ts >= date_trunc('day', now()) - interval '1 day'     then 'updated yesterday'
    when ts >= now() - interval '7 days'
      then 'updated ' || greatest(extract(day from now() - ts)::int, 2) || ' days ago'
    when ts >= now() - interval '14 days'                      then 'updated this week'
    else 'updated recently'
  end;
$$;

-- Fallback origin when the app has no location fix yet: KNUST campus centre.
create or replace function public.default_origin()
returns table (lat double precision, lng double precision)
language sql immutable parallel safe as $$
  select 6.67470::double precision, -1.57130::double precision;
$$;

-- May the caller add/edit floors, rooms, landmarks and routes in this
-- building? True for the creator and for anyone already a contributor.
-- security definer so the check itself is not filtered by the policies that
-- call it.
create or replace function public.can_edit_building(p_building_id text)
returns boolean
language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.buildings b
    where b.id = p_building_id and b.created_by = auth.uid()
  ) or exists (
    select 1 from public.building_contributors c
    where c.building_id = p_building_id and c.user_id = auth.uid()
  );
$$;

-- ===========================================================================
-- 4 · View + RPCs
-- ===========================================================================

-- A building row shaped exactly like the Building model.
-- security_invoker keeps the caller's RLS in force (PG15+).
create or replace view public.buildings_view with (security_invoker = on) as
select
  b.id,
  b.name,
  b.area,
  b.category,
  b.glyph,
  b.mapped_percent,
  b.lat,
  b.lng,
  b.updated_at,
  (select count(*) from public.floors f where f.building_id = b.id)::int
    as floors_count,
  (b.seed_mappers +
   (select count(*) from public.building_contributors c where c.building_id = b.id))::int
    as mappers,
  public.updated_label(b.updated_at) as updated_label,
  public.haversine_km(o.lat, o.lng, b.lat, b.lng) as distance_km
from public.buildings b
cross join lateral public.default_origin() o;

-- Explore: category chip + search box, sorted by distance from the caller.
create or replace function public.nearby_buildings(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_category text default 'all',
  p_query    text default ''
)
returns table (
  id text, name text, area text, category text, glyph text,
  mapped_percent int, floors_count int, mappers int,
  updated_label text, distance_km double precision
)
language sql stable
set search_path = public as $$
  select
    v.id, v.name, v.area, v.category, v.glyph,
    v.mapped_percent, v.floors_count, v.mappers, v.updated_label,
    public.haversine_km(
      coalesce(p_lat, o.lat), coalesce(p_lng, o.lng), v.lat, v.lng
    ) as distance_km
  from public.buildings_view v
  cross join lateral public.default_origin() o
  where (p_category = 'all' or v.category = p_category)
    and (coalesce(p_query, '') = '' or v.name ilike '%' || p_query || '%')
  order by distance_km, v.name;
$$;

-- Home "Recently mapped": the caller's own contributions, newest first. A
-- brand-new account has none, which would leave Home empty — so fall back to
-- the most recently updated buildings overall.
create or replace function public.recently_mapped_buildings(p_limit int default 4)
returns table (
  id text, name text, area text, category text, glyph text,
  mapped_percent int, floors_count int, mappers int,
  updated_label text, distance_km double precision
)
language sql stable
set search_path = public as $$
  with mine as (
    select v.*, c.updated_at as contributed_at
    from public.building_contributors c
    join public.buildings_view v on v.id = c.building_id
    where c.user_id = auth.uid()
    order by c.updated_at desc
    limit p_limit
  ),
  fallback as (
    select v.*, v.updated_at as contributed_at
    from public.buildings_view v
    where not exists (select 1 from mine)
    order by v.updated_at desc
    limit p_limit
  ),
  picked as (select * from mine union all select * from fallback)
  select
    p.id, p.name, p.area, p.category, p.glyph,
    p.mapped_percent, p.floors_count, p.mappers, p.updated_label, p.distance_km
  from picked p
  order by p.contributed_at desc;
$$;

-- Profile tab: mapping totals for the signed-in contributor.
create or replace function public.contributor_stats()
returns table (buildings_mapped int, floors_mapped int, rooms_mapped int)
language sql stable
set search_path = public as $$
  select
    count(*)::int,
    coalesce(sum(c.floors_mapped), 0)::int,
    coalesce(sum(c.rooms_mapped), 0)::int
  from public.building_contributors c
  where c.user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- save_route — atomic capture upload
--
-- PostgREST cannot span statements in one transaction, and a half-written
-- route (landmarks but no legs) is corrupt data the map would silently
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
  -- bookkeeping: can_edit_building gates every write below, and a seeded
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

-- ===========================================================================
-- 5 · Triggers
-- ===========================================================================

-- Every new auth user gets a profile row. security definer because the row is
-- written before the user has a session to authorise it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    coalesce(new.email, '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Stamps updated_at on every write, unless the statement set it explicitly
-- (seeds and backfills need to write a past timestamp).
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists buildings_touch_updated_at on public.buildings;
create trigger buildings_touch_updated_at
  before update on public.buildings
  for each row execute function public.touch_updated_at();

drop trigger if exists contributors_touch_updated_at on public.building_contributors;
create trigger contributors_touch_updated_at
  before update on public.building_contributors
  for each row execute function public.touch_updated_at();

-- Editing a floor or room counts as touching its building, so "updated today"
-- reflects mapping work and not just edits to the building header.
create or replace function public.touch_building_from_floor()
returns trigger language plpgsql
set search_path = public as $$
begin
  update public.buildings
     set updated_at = now()
   where id = coalesce(new.building_id, old.building_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists floors_touch_building on public.floors;
create trigger floors_touch_building
  after insert or update or delete on public.floors
  for each row execute function public.touch_building_from_floor();

create or replace function public.touch_building_from_room()
returns trigger language plpgsql
set search_path = public as $$
begin
  update public.buildings b
     set updated_at = now()
    from public.floors f
   where f.id = coalesce(new.floor_id, old.floor_id)
     and b.id = f.building_id;
  return coalesce(new, old);
end;
$$;

drop trigger if exists rooms_touch_building on public.rooms;
create trigger rooms_touch_building
  after insert or update or delete on public.rooms
  for each row execute function public.touch_building_from_room();

-- ===========================================================================
-- 6 · Row Level Security
--
-- The map index is public-read to any signed-in user (that is the point of
-- crowdsourcing); writes are restricted to the building's creator or an
-- existing contributor. Personal rows (profile, saved maps) are owner-only.
-- ===========================================================================

alter table public.profiles              enable row level security;
alter table public.buildings             enable row level security;
alter table public.floors                enable row level security;
alter table public.rooms                 enable row level security;
alter table public.building_contributors enable row level security;
alter table public.saved_maps            enable row level security;
alter table public.landmarks             enable row level security;
alter table public.routes                enable row level security;
alter table public.route_steps           enable row level security;

-- profiles
drop policy if exists "profiles readable by signed-in users" on public.profiles;
create policy "profiles readable by signed-in users"
  on public.profiles for select to authenticated using (true);

drop policy if exists "profiles updatable by owner" on public.profiles;
create policy "profiles updatable by owner"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- buildings
drop policy if exists "buildings readable by signed-in users" on public.buildings;
create policy "buildings readable by signed-in users"
  on public.buildings for select to authenticated using (true);

drop policy if exists "buildings insertable by signed-in users" on public.buildings;
create policy "buildings insertable by signed-in users"
  on public.buildings for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists "buildings editable by contributors" on public.buildings;
create policy "buildings editable by contributors"
  on public.buildings for update to authenticated
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.building_contributors c
      where c.building_id = buildings.id and c.user_id = auth.uid()
    )
  );

-- floors / rooms: same contributor rule, reached through the parent building
drop policy if exists "floors readable by signed-in users" on public.floors;
create policy "floors readable by signed-in users"
  on public.floors for select to authenticated using (true);

drop policy if exists "floors writable by contributors" on public.floors;
create policy "floors writable by contributors"
  on public.floors for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

drop policy if exists "rooms readable by signed-in users" on public.rooms;
create policy "rooms readable by signed-in users"
  on public.rooms for select to authenticated using (true);

drop policy if exists "rooms writable by contributors" on public.rooms;
create policy "rooms writable by contributors"
  on public.rooms for all to authenticated
  using (
    exists (
      select 1 from public.floors f
      where f.id = rooms.floor_id and public.can_edit_building(f.building_id)
    )
  )
  with check (
    exists (
      select 1 from public.floors f
      where f.id = rooms.floor_id and public.can_edit_building(f.building_id)
    )
  );

-- building_contributors
drop policy if exists "contributors readable by signed-in users"
  on public.building_contributors;
create policy "contributors readable by signed-in users"
  on public.building_contributors for select to authenticated using (true);

drop policy if exists "contributors manage own row" on public.building_contributors;
create policy "contributors manage own row"
  on public.building_contributors for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- saved_maps — strictly private
drop policy if exists "saved maps are owner-only" on public.saved_maps;
create policy "saved maps are owner-only"
  on public.saved_maps for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- landmarks / routes / route_steps
drop policy if exists "landmarks readable by signed-in users" on public.landmarks;
create policy "landmarks readable by signed-in users"
  on public.landmarks for select to authenticated using (true);

drop policy if exists "landmarks writable by contributors" on public.landmarks;
create policy "landmarks writable by contributors"
  on public.landmarks for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

drop policy if exists "routes readable by signed-in users" on public.routes;
create policy "routes readable by signed-in users"
  on public.routes for select to authenticated using (true);

drop policy if exists "routes writable by contributors" on public.routes;
create policy "routes writable by contributors"
  on public.routes for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

drop policy if exists "route steps readable by signed-in users" on public.route_steps;
create policy "route steps readable by signed-in users"
  on public.route_steps for select to authenticated using (true);

drop policy if exists "route steps writable by contributors" on public.route_steps;
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

-- ===========================================================================
-- 7 · Seed — buildings, floors, rooms
--
-- Coordinates are approximate. Replace with GPS readings taken during field
-- mapping.
-- ===========================================================================

insert into public.buildings
  (id, name, area, category, glyph, mapped_percent, lat, lng, seed_mappers)
values
  ('knust-library',     'KNUST Library',     'KNUST, Kumasi',   'campus',   'building', 94, 6.67650, -1.57130, 12),
  ('engineering-block', 'Engineering Block', 'KNUST, Kumasi',   'campus',   'door',     71, 6.67110, -1.57130,  8),
  ('src-building',      'SRC Building',      'KNUST, Kumasi',   'campus',   'home',     42, 6.66930, -1.57130,  3),
  ('great-hall',        'Great Hall',        'KNUST, Kumasi',   'campus',   'hall',     88, 6.67920, -1.57130,  6),
  ('cabs-block',        'CABS Block',        'KNUST, Kumasi',   'campus',   'building', 87, 6.67470, -1.56858,  4),
  ('science-block',     'Science Block',     'KNUST, Kumasi',   'campus',   'door',     62, 6.67470, -1.57492,  2),
  ('kath-wing-a',       'KATH — Wing A',     'Bantama, Kumasi', 'hospital', 'building', 55, 6.69750, -1.63180,  5),
  ('kumasi-city-mall',  'Kumasi City Mall',  'Asokwa, Kumasi',  'mall',     'hall',     77, 6.67840, -1.60860,  9)
on conflict (id) do update set
  name           = excluded.name,
  area           = excluded.area,
  category       = excluded.category,
  glyph          = excluded.glyph,
  mapped_percent = excluded.mapped_percent,
  lat            = excluded.lat,
  lng            = excluded.lng,
  seed_mappers   = excluded.seed_mappers;

-- Floor counts match the design; room names follow the mock repository,
-- except KNUST Library floor 2, which is the floor drawn in Building Detail
-- (Figma 7:301) and the floor both seeded routes end on.
do $$
declare
  b            record;
  i            int;
  floor_label  text;
  new_floor_id uuid;
begin
  for b in
    select * from (values
      ('knust-library', 4), ('engineering-block', 5), ('src-building', 2),
      ('great-hall', 1),    ('cabs-block', 3),        ('science-block', 2),
      ('kath-wing-a', 3),   ('kumasi-city-mall', 2)
    ) as t(id, floors)
  loop
    for i in 0 .. b.floors - 1 loop
      floor_label := case when i = 0 then 'G' else i::text end;

      insert into public.floors (building_id, label, ordinal)
      values (b.id, floor_label, i)
      on conflict (building_id, ordinal) do update set label = excluded.label
      returning id into new_floor_id;

      -- Re-seeding replaces a floor's rooms rather than duplicating them.
      -- Rooms referenced by a landmark or a route are left alone: deleting
      -- them would cascade away real captured data.
      delete from public.rooms r
       where r.floor_id = new_floor_id
         and not exists (select 1 from public.landmarks l where l.room_id = r.id)
         and not exists (select 1 from public.routes  rt where rt.destination_room_id = r.id);

      if b.id = 'knust-library' and i = 2 then
        insert into public.rooms (floor_id, name, kind, distance_m)
        select new_floor_id, v.name, v.kind, v.distance_m
        from (values
          ('Reading Hall',  'hall', 40),
          ('Study Room 2B', 'room', 65),
          ('Help Desk',     'desk', 20)
        ) as v(name, kind, distance_m)
        where not exists (
          select 1 from public.rooms r
          where r.floor_id = new_floor_id and r.name = v.name
        );
      else
        insert into public.rooms (floor_id, name, kind, distance_m)
        select new_floor_id, v.name, v.kind, v.distance_m
        from (values
          ('Room ' || floor_label || '01', 'room', 25),
          ('Room ' || floor_label || '02', 'room', 45),
          ('Washroom',                     'desk', 30)
        ) as v(name, kind, distance_m)
        where not exists (
          select 1 from public.rooms r
          where r.floor_id = new_floor_id and r.name = v.name
        );
      end if;
    end loop;
  end loop;
end $$;

-- Freshness labels last: inserting floors/rooms fires the triggers that bump
-- buildings.updated_at, so any values set earlier would be lost.
update public.buildings set updated_at = now()                     where id in ('knust-library', 'cabs-block', 'kumasi-city-mall');
update public.buildings set updated_at = now() - interval '1 day'  where id in ('engineering-block', 'science-block');
update public.buildings set updated_at = now() - interval '3 days' where id = 'src-building';
update public.buildings set updated_at = now() - interval '9 days' where id in ('great-hall', 'kath-wing-a');

-- Backfill profiles for accounts created before handle_new_user() existed.
-- Without this, an existing user has no profiles row, and every table that
-- references it rejects their writes with a foreign-key violation.
insert into public.profiles (id, full_name, email)
select
  u.id,
  coalesce(
    u.raw_user_meta_data ->> 'full_name',
    u.raw_user_meta_data ->> 'name',
    split_part(coalesce(u.email, ''), '@', 1)
  ),
  coalesce(u.email, '')
from auth.users u
on conflict (id) do nothing;

-- ===========================================================================
-- 8 · Seed — two hand-authored routes through KNUST Library
--
-- Two, not one, and deliberately overlapping: they share their first four legs
-- and diverge at the floor 2 directory board. One route on its own can only
-- ever be replayed; two that cross are what make A* meaningful, because the
-- app can then answer "Reading Hall to Study Room 2B" — a journey nobody
-- walked end to end.
--
-- Distances and instructions are plausible placeholders, NOT surveyed. The
-- first genuine field capture should replace both wholesale.
-- ===========================================================================

do $$
declare
  v_building   constant text := 'knust-library';
  v_floor_g    uuid;
  v_floor_2    uuid;
  v_reading    uuid;
  v_study      uuid;
  v_entrance   uuid;
  v_desk       uuid;
  v_stairs_g   uuid;
  v_landing_2  uuid;
  v_corridor_2 uuid;
  v_door_r     uuid;
  v_door_s     uuid;
  v_route      uuid;
begin
  select id into v_floor_g from public.floors
   where building_id = v_building and ordinal = 0;
  select id into v_floor_2 from public.floors
   where building_id = v_building and ordinal = 2;

  if v_floor_g is null or v_floor_2 is null then
    raise notice 'seed routes: KNUST Library floors missing — skipped';
    return;
  end if;

  select id into v_reading from public.rooms
   where floor_id = v_floor_2 and name = 'Reading Hall';
  select id into v_study   from public.rooms
   where floor_id = v_floor_2 and name = 'Study Room 2B';

  if v_reading is null or v_study is null then
    raise notice 'seed routes: KNUST Library rooms missing — skipped';
    return;
  end if;

  -- Landmarks -------------------------------------------------------------
  insert into public.landmarks
    (building_id, floor_id, kind, label_text, aliases, display_name, room_id)
  values
    (v_building, v_floor_g, 'entrance', 'KNUST LIBRARY', '{}',                            'Main entrance',           null),
    (v_building, v_floor_g, 'junction', 'HELP DESK',     '{"HELPDESK"}',                  'Help desk',               null),
    (v_building, v_floor_g, 'stairs',   'STAIRS',        '{"STAIRWAY"}',                  'Ground floor stairwell',  null),
    (v_building, v_floor_2, 'stairs',   '2',             '{"FLOOR 2","2ND"}',             'Floor 2 landing',         null),
    (v_building, v_floor_2, 'sign',     'ROOMS 201-210', '{"ROOMS 201 - 210","201-210"}', 'Floor 2 directory board', null),
    (v_building, v_floor_2, 'door',     'READING HALL',  '{"READINGHALL"}',               'Reading Hall door',       v_reading),
    (v_building, v_floor_2, 'door',     '2B',            '{"28","2 B"}',                  'Study Room 2B door',      v_study)
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
  select id into v_door_r     from public.landmarks
   where building_id = v_building and display_name = 'Reading Hall door';
  select id into v_door_s     from public.landmarks
   where building_id = v_building and display_name = 'Study Room 2B door';

  -- Route 1: Main entrance -> Reading Hall (53 m over 5 legs) --------------
  -- `created_by is null` means only the seed is ever removed, never a real
  -- capture.
  delete from public.routes
   where building_id = v_building
     and destination_room_id = v_reading
     and created_by is null;

  insert into public.routes
    (building_id, start_landmark_id, destination_room_id, total_distance_m)
  values (v_building, v_entrance, v_reading, 53)
  returning id into v_route;

  insert into public.route_steps
    (route_id, seq, from_landmark_id, to_landmark_id, instruction,
     distance_m, steps_recorded, turn_deg)
  values
    (v_route, 1, v_entrance,   v_desk,       'Straight ahead, past the entrance desk',                          12, 16,  0),
    (v_route, 2, v_desk,       v_stairs_g,   'Turn right; the stairwell is at the end of the corridor',         18, 24, 90),
    (v_route, 3, v_stairs_g,   v_landing_2,  'Take the stairs up two flights to floor 2',                        8, 11,  0),
    (v_route, 4, v_landing_2,  v_corridor_2, 'Turn left along the main corridor to the directory board',          9, 12, -90),
    (v_route, 5, v_corridor_2, v_door_r,     'Straight on; the Reading Hall is the second door on your right',    6,  8,  0);

  -- Route 2: Main entrance -> Study Room 2B (54 m over 5 legs) -------------
  -- Shares legs 1-4 with route 1; diverges at the directory board.
  delete from public.routes
   where building_id = v_building
     and destination_room_id = v_study
     and created_by is null;

  insert into public.routes
    (building_id, start_landmark_id, destination_room_id, total_distance_m)
  values (v_building, v_entrance, v_study, 54)
  returning id into v_route;

  insert into public.route_steps
    (route_id, seq, from_landmark_id, to_landmark_id, instruction,
     distance_m, steps_recorded, turn_deg)
  values
    (v_route, 1, v_entrance,   v_desk,       'Straight ahead, past the entrance desk',                          12, 16,  0),
    (v_route, 2, v_desk,       v_stairs_g,   'Turn right; the stairwell is at the end of the corridor',         18, 25, 90),
    (v_route, 3, v_stairs_g,   v_landing_2,  'Take the stairs up two flights to floor 2',                        8, 11,  0),
    (v_route, 4, v_landing_2,  v_corridor_2, 'Turn left along the main corridor to the directory board',          9, 12, -90),
    (v_route, 5, v_corridor_2, v_door_s,     'Turn right; Study Room 2B is the first door on your left',          7,  9, 90);

  raise notice 'seed routes: both KNUST Library routes written';
end $$;

-- ===========================================================================
-- 9 · Verification
--
-- The seed blocks above bail out quietly when a prerequisite is missing, and
-- the SQL editor does not surface NOTICE prominently — so a skipped seed looks
-- exactly like a successful one. This is how you tell.
--
-- Every row should read OK.
-- ===========================================================================

select
  t.ord,
  t.item,
  t.actual,
  t.expected,
  case when t.actual = t.expected then 'OK' else '>>> CHECK THIS' end as status
from (
  select 1 as ord, 'buildings' as item,
         (select count(*) from public.buildings)::text as actual,
         '8' as expected
  union all
  select 2, 'KNUST Library floors',
         (select count(*) from public.floors where building_id = 'knust-library')::text,
         '4'
  union all
  select 3, 'KNUST Library landmarks',
         (select count(*) from public.landmarks where building_id = 'knust-library')::text,
         '7'
  union all
  select 4, 'KNUST Library routes',
         (select count(*) from public.routes where building_id = 'knust-library')::text,
         '2'
  union all
  select 5, 'Reading Hall legs',
         (select count(*) from public.route_steps rs
            join public.routes r  on r.id  = rs.route_id
            join public.rooms  rm on rm.id = r.destination_room_id
           where r.building_id = 'knust-library' and rm.name = 'Reading Hall')::text,
         '5'
  union all
  select 6, 'Study Room 2B legs',
         (select count(*) from public.route_steps rs
            join public.routes r  on r.id  = rs.route_id
            join public.rooms  rm on rm.id = r.destination_room_id
           where r.building_id = 'knust-library' and rm.name = 'Study Room 2B')::text,
         '5'
  union all
  -- The overlap is the whole point: without shared landmarks the two routes
  -- are two disconnected wings and A* can never join them.
  select 7, 'landmarks the two routes share',
         (select count(*) from (
            select rs.from_landmark_id as id from public.route_steps rs
              join public.routes r on r.id = rs.route_id
             where r.building_id = 'knust-library'
             group by rs.from_landmark_id
            having count(distinct rs.route_id) > 1
          ) shared)::text,
         '5'
  union all
  select 8, 'save_route function',
         (select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where p.proname = 'save_route' and n.nspname = 'public')::text,
         '1'
  union all
  select 9, 'RLS-protected tables',
         (select count(*) from pg_tables
           where schemaname = 'public' and rowsecurity
             and tablename in ('profiles','buildings','floors','rooms',
                               'building_contributors','saved_maps',
                               'landmarks','routes','route_steps'))::text,
         '9'
) t
order by t.ord;
