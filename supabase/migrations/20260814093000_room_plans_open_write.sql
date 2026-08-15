-- Prototype: any signed-in contributor may write a room plan.
--
-- `room_plans_write` gated on can_edit_building(), which is true only when
-- buildings.created_by = auth.uid() or a building_contributors row exists. The
-- seeded buildings have neither: 20260731090100 inserts knust-library leaving
-- created_by NULL, and its own comment admits "seeded buildings have no real
-- contributor rows (those need real auth users)". NULL = auth.uid() is never
-- true, so can_edit_building() was false for *every* account and nobody could
-- save a plan for the building the app ships pointing at. It cost a
-- contributor twenty minutes of tracing before it was found.
--
-- The gate is opened rather than the seed repaired because this is a
-- prototype and tracing has to work today. It is deliberately permissive:
-- any signed-in account can now replace any floor's plan, including one it has
-- no claim to. That is not a policy to put in front of real users. The proper
-- fix is for a building to acquire an owner when it is created — and for
-- seeded buildings to name one — at which point can_edit_building() can come
-- back for writes. Reads were always public and stay that way.
--
-- Scoped to room_plans on purpose. `routes` and `traced_plans` gate on the
-- same function and will fail the same way on a seeded building; they are left
-- alone here rather than quietly widened along with this one.

drop policy if exists room_plans_write on public.room_plans;

create policy room_plans_write
  on public.room_plans for all
  to authenticated
  using (true)
  with check (true);

comment on table public.room_plans is
  'One traced room plan per building floor: polygons, categories, and the '
  'doors between them. Prototype: writable by any signed-in user.';
