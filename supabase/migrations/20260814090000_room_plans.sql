-- Traced room geometry.
--
-- The third source of a building's shape, and the only one that knows how wide
-- a room is. `routes` holds walks people recorded (positions chained from step
-- counts, so they drift); `traced_plans` holds landmark *points* read off the
-- posted floor plan; this holds room *areas* read off the same plan — the
-- polygons, what each room is for, and the doors between them.
--
-- What the areas buy is one sentence guidance cannot otherwise say: "your
-- destination is the second door on your left". That needs to know which wall a
-- door is in and what else is on that wall, which a point has no way to
-- express.
--
-- One jsonb document per floor, following `traced_plans` rather than splitting
-- into rooms/openings tables: it is written and read whole, never queried into,
-- and one row is what makes "replace this floor's plan" a single statement that
-- cannot half-apply. Per *floor* rather than per building because each floor
-- has its own board on its own wall and is traced in its own sitting.

create table if not exists public.room_plans (
  building_id text not null
    references public.buildings (id) on delete cascade,
  floor_id    text        not null,
  plan        jsonb       not null,
  traced_by   uuid        references auth.users (id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (building_id, floor_id)
);

comment on table public.room_plans is
  'One traced room plan per building floor: polygons, categories, and the doors between them.';

create index if not exists room_plans_building_idx
  on public.room_plans (building_id);

alter table public.room_plans enable row level security;

-- Anyone may read. Navigating a building you have never contributed to is the
-- entire point of sharing these.
drop policy if exists room_plans_read on public.room_plans;
create policy room_plans_read
  on public.room_plans for select
  using (true);

-- Writes gate on can_edit_building, the same as routes and traced plans.
drop policy if exists room_plans_write on public.room_plans;
create policy room_plans_write
  on public.room_plans for all
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

drop trigger if exists room_plans_touch on public.room_plans;
create trigger room_plans_touch
  before update on public.room_plans
  for each row execute function public.touch_updated_at();

-- Stores one floor's rooms, replacing whatever that floor had.
--
-- Replace rather than merge, deliberately: two contributors tracing the same
-- floor have produced two opinions of the same geometry, and merging polygons
-- is not something that can be done sensibly without asking a human which is
-- right. Last write wins, and a floor takes about fifteen minutes to retrace.
--
-- Keys are read as camelCase because the payload is `RoomPlan.toJson()` handed
-- over unchanged — the same thing that caught out `save_traced_plan`, which
-- looked for 'building_id' and found nothing on every single save.
create or replace function public.save_room_plan(p_plan jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public as $$
declare
  v_building text := p_plan ->> 'buildingId';
  v_floor    text := p_plan ->> 'floorId';
begin
  if v_building is null or v_building = '' then
    raise exception 'save_room_plan: buildingId is required';
  end if;

  if v_floor is null or v_floor = '' then
    raise exception 'save_room_plan: floorId is required';
  end if;

  -- A plan with no rooms is a plan that would erase the floor it replaces.
  -- Deleting a traced floor is a real thing to want, but it is not this, and
  -- an empty save is far more likely to be a bug than an intention.
  if jsonb_array_length(coalesce(p_plan -> 'rooms', '[]'::jsonb)) = 0 then
    raise exception 'save_room_plan: a plan needs at least one room';
  end if;

  insert into public.room_plans (building_id, floor_id, plan, traced_by)
  values (v_building, v_floor, p_plan, auth.uid())
  on conflict (building_id, floor_id) do update
    set plan       = excluded.plan,
        traced_by  = excluded.traced_by,
        updated_at = now();

  return p_plan;
end;
$$;

comment on function public.save_room_plan(jsonb) is
  'Upserts one floor''s traced room plan. Payload is RoomPlan.toJson().';
