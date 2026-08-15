-- Saving a traced floor now credits the person who traced it.
--
-- `save_room_plan` wrote `room_plans` and nothing else, which left two things
-- quietly wrong:
--
--   * **The mapper never became a contributor.** `recently_mapped_buildings`
--     shows the buildings you have a `building_contributors` row for and only
--     falls back to "whatever was updated last" when you have none. Trace a
--     whole floor and Home still would not list the building, because nothing
--     ever inserted the row.
--   * **The building never looked touched.** `buildings.updated_at` is what the
--     fallback orders by and what "updated this week" reads from. A floor
--     traced today left a building last updated at its seed date.
--
-- Order matters and is the reason this needs no elevated rights: `buildings` is
-- updatable only by a contributor, and inserting the contributor row is exactly
-- what makes the caller one. Contributor first, building second, both under the
-- caller's own permissions.
--
-- The counts are recomputed from `room_plans` rather than incremented, so
-- re-saving the same floor does not inflate them and a floor traced by two
-- people credits each with what they actually hold.

create or replace function public.save_room_plan(p_plan jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public as $$
declare
  v_building text := p_plan ->> 'buildingId';
  v_floor    text := p_plan ->> 'floorId';
  v_floors   int;
  v_rooms    int;
begin
  if v_building is null or v_building = '' then
    raise exception 'save_room_plan: buildingId is required';
  end if;

  if v_floor is null or v_floor = '' then
    raise exception 'save_room_plan: floorId is required';
  end if;

  -- A plan with no rooms is a plan that would erase the floor it replaces.
  if jsonb_array_length(coalesce(p_plan -> 'rooms', '[]'::jsonb)) = 0 then
    raise exception 'save_room_plan: a plan needs at least one room';
  end if;

  insert into public.room_plans (building_id, floor_id, plan, traced_by)
  values (v_building, v_floor, p_plan, auth.uid())
  on conflict (building_id, floor_id) do update
    set plan       = excluded.plan,
        traced_by  = excluded.traced_by,
        updated_at = now();

  -- Anonymous callers can still write a plan (the prototype policy allows it);
  -- there is simply nobody to credit.
  if auth.uid() is not null then
    select count(*),
           coalesce(sum(jsonb_array_length(coalesce(plan -> 'rooms', '[]'::jsonb))), 0)
      into v_floors, v_rooms
      from public.room_plans
     where building_id = v_building
       and traced_by = auth.uid();

    insert into public.building_contributors
      (building_id, user_id, floors_mapped, rooms_mapped)
    values (v_building, auth.uid(), v_floors, v_rooms)
    on conflict (building_id, user_id) do update
      set floors_mapped = v_floors,
          rooms_mapped  = v_rooms,
          updated_at    = now();

    update public.buildings set updated_at = now() where id = v_building;
  end if;

  return p_plan;
end;
$$;

comment on function public.save_room_plan(jsonb) is
  'Upserts one floor''s traced room plan, credits the tracer as a building '
  'contributor, and marks the building updated. Payload is RoomPlan.toJson().';
