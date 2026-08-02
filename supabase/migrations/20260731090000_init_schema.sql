-- EchoLocate v2 — core schema
--
-- Tables mirror the app's freezed models (lib/core/models/building.dart,
-- user_profile.dart). Everything the UI shows that is *derived* — floor
-- counts, mapper counts, "updated today", distance — is computed here in
-- `buildings_view` / the RPCs rather than stored, so a building row never
-- goes stale against its own children.
--
-- Column names stay snake_case; the Dart repository maps them to the models'
-- camelCase keys (SupabaseBuildingRepository._buildingFrom).

-- ---------------------------------------------------------------------------
-- profiles — one row per auth user, created by trigger on sign-up
-- ---------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  email       text not null default '',
  created_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Contributor identity. Populated from auth.users metadata by handle_new_user().';

-- ---------------------------------------------------------------------------
-- buildings — the crowdsourced index
-- ---------------------------------------------------------------------------
create table public.buildings (
  id              text primary key,          -- slug, e.g. 'knust-library'
  name            text not null,
  area            text not null,             -- "KNUST, Kumasi"
  category        text not null default 'campus'
                    check (category in ('campus', 'hospital', 'mall', 'office', 'other')),
  glyph           text not null default 'building'
                    check (glyph in ('building', 'door', 'home', 'hall', 'book')),
  mapped_percent  int  not null default 0
                    check (mapped_percent between 0 and 100),
  lat             double precision,
  lng             double precision,
  -- Demo scaffolding only: seeded buildings have no real contributor rows
  -- (those need real auth users), so the cards would all read "0 mappers".
  -- Added to the live count in buildings_view. Real buildings created in-app
  -- leave this at 0.
  seed_mappers    int  not null default 0,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index buildings_category_idx on public.buildings (category);

-- ---------------------------------------------------------------------------
-- floors / rooms
-- ---------------------------------------------------------------------------
create table public.floors (
  id           uuid primary key default gen_random_uuid(),
  building_id  text not null references public.buildings (id) on delete cascade,
  label        text not null,   -- 'G', '1', '2' — shown on the floor chips
  ordinal      int  not null,   -- 0-based; sort key
  created_at   timestamptz not null default now(),
  unique (building_id, ordinal)
);

create index floors_building_idx on public.floors (building_id);

create table public.rooms (
  id          uuid primary key default gen_random_uuid(),
  floor_id    uuid not null references public.floors (id) on delete cascade,
  name        text not null,
  kind        text not null default 'room'
                check (kind in ('room', 'hall', 'desk')),
  distance_m  int  not null default 0,   -- metres from the floor entrance
  created_at  timestamptz not null default now()
);

create index rooms_floor_idx on public.rooms (floor_id);

-- ---------------------------------------------------------------------------
-- building_contributors — who mapped what. Drives the "N mappers" count on
-- every card and the contributor stats on the Profile tab.
-- ---------------------------------------------------------------------------
create table public.building_contributors (
  building_id   text not null references public.buildings (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  floors_mapped int not null default 0,
  rooms_mapped  int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (building_id, user_id)
);

create index building_contributors_user_idx on public.building_contributors (user_id);

-- ---------------------------------------------------------------------------
-- saved_maps — buildings a user keeps for offline use (Maps tab)
-- ---------------------------------------------------------------------------
create table public.saved_maps (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  building_id text not null references public.buildings (id) on delete cascade,
  saved_at    timestamptz not null default now(),
  primary key (user_id, building_id)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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

-- "updated today" / "updated yesterday" / "updated 3 days ago" — the exact
-- strings the cards render, so the client never formats dates.
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

-- May the caller add/edit floors and rooms in this building? True for the
-- creator and for anyone already listed as a contributor. security definer so
-- the check itself is not filtered by the policies that call it.
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

-- ---------------------------------------------------------------------------
-- buildings_view — a building row shaped exactly like the Building model.
-- security_invoker keeps the caller's RLS in force (PG15+).
-- ---------------------------------------------------------------------------
create view public.buildings_view with (security_invoker = on) as
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

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Explore: category chip + search box, sorted by distance from the caller's
-- position (falls back to the campus origin when the app has no fix).
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

-- Home "Recently mapped": the caller's own contributions, newest first.
-- A brand-new account has none, which would leave Home empty — so we fall
-- back to the most recently updated buildings overall.
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
-- Triggers
-- ---------------------------------------------------------------------------

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

create trigger buildings_touch_updated_at
  before update on public.buildings
  for each row execute function public.touch_updated_at();

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

create trigger rooms_touch_building
  after insert or update or delete on public.rooms
  for each row execute function public.touch_building_from_room();

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- The map index is public-read to any signed-in user (that is the point of
-- crowdsourcing); writes are restricted to the building's creator or an
-- existing contributor. Personal rows (profile, saved maps) are owner-only.
-- ---------------------------------------------------------------------------
alter table public.profiles              enable row level security;
alter table public.buildings             enable row level security;
alter table public.floors                enable row level security;
alter table public.rooms                 enable row level security;
alter table public.building_contributors enable row level security;
alter table public.saved_maps            enable row level security;

-- profiles
create policy "profiles readable by signed-in users"
  on public.profiles for select to authenticated using (true);
create policy "profiles updatable by owner"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- buildings
create policy "buildings readable by signed-in users"
  on public.buildings for select to authenticated using (true);
create policy "buildings insertable by signed-in users"
  on public.buildings for insert to authenticated
  with check (created_by = auth.uid());
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
create policy "floors readable by signed-in users"
  on public.floors for select to authenticated using (true);
create policy "floors writable by contributors"
  on public.floors for all to authenticated
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

create policy "rooms readable by signed-in users"
  on public.rooms for select to authenticated using (true);
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
create policy "contributors readable by signed-in users"
  on public.building_contributors for select to authenticated using (true);
create policy "contributors manage own row"
  on public.building_contributors for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- saved_maps — strictly private
create policy "saved maps are owner-only"
  on public.saved_maps for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
