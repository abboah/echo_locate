-- Traced floor plans.
--
-- The alternative source of a building's geometry. `routes` holds walks people
-- recorded, whose positions are chained from step counts and tapped turns and
-- therefore drift; a traced plan holds coordinates read straight off the floor
-- plan posted on the building's wall, so nothing accumulates and loops close.
--
-- Stored as one jsonb document per building rather than a nodes/edges pair of
-- tables: it is written and read whole, never queried into, and keeping it in
-- one row is what makes "replace the building's plan" a single statement that
-- cannot half-apply.

create table if not exists public.traced_plans (
  building_id text primary key
    references public.buildings (id) on delete cascade,
  plan        jsonb       not null,
  traced_by   uuid        references auth.users (id) on delete set null,
  updated_at  timestamptz not null default now()
);

comment on table public.traced_plans is
  'One traced floor plan per building. Node refs inside `plan` are landmark ids.';

alter table public.traced_plans enable row level security;

-- Anyone may read a plan: navigating a building you have never contributed to
-- is the entire point of sharing them.
drop policy if exists traced_plans_read on public.traced_plans;
create policy traced_plans_read
  on public.traced_plans for select
  using (true);

-- Writes go through save_traced_plan, which gates on can_edit_building the
-- same way save_route does.
drop policy if exists traced_plans_write on public.traced_plans;
create policy traced_plans_write
  on public.traced_plans for all
  using (public.can_edit_building(building_id))
  with check (public.can_edit_building(building_id));

drop trigger if exists traced_plans_touch on public.traced_plans;
create trigger traced_plans_touch
  before update on public.traced_plans
  for each row execute function public.touch_updated_at();

-- Upserts every node as a landmark, rewrites the plan's refs to those ids, and
-- stores the result — all in one transaction, so a dropped connection can never
-- leave a plan referencing landmarks that were not created.
--
-- Returns the resolved plan, so the client's in-memory graph and the stored one
-- are the same document rather than two things that have to be kept in step.
create or replace function public.save_traced_plan(p_plan jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public as $$
declare
  v_building text := p_plan ->> 'building_id';
  v_refs     jsonb := '{}'::jsonb;   -- ref -> landmark uuid
  v_node     jsonb;
  v_edge     jsonb;
  v_id       uuid;
  v_nodes    jsonb := '[]'::jsonb;
  v_edges    jsonb := '[]'::jsonb;
  v_from     text;
  v_to       text;
  v_result   jsonb;
begin
  if v_building is null then
    raise exception 'save_traced_plan: building_id is required';
  end if;

  if jsonb_array_length(coalesce(p_plan -> 'nodes', '[]'::jsonb)) = 0 then
    raise exception 'save_traced_plan: a plan needs at least one node';
  end if;

  -- Tracing a building makes you a contributor to it, for the same reason
  -- recording a route does: can_edit_building gates the write below, and a
  -- seeded building has no contributors yet.
  insert into public.building_contributors (building_id, user_id)
  values (v_building, auth.uid())
  on conflict (building_id, user_id) do nothing;

  for v_node in select * from jsonb_array_elements(p_plan -> 'nodes')
  loop
    insert into public.landmarks
      (building_id, floor_id, kind, label_text, aliases, display_name,
       room_id, created_by)
    values (
      v_building,
      (v_node ->> 'floorId')::uuid,
      v_node ->> 'kind',
      upper(trim(v_node ->> 'labelText')),
      coalesce(
        (select array_agg(value::text)
           from jsonb_array_elements_text(v_node -> 'aliases')),
        '{}'
      ),
      v_node ->> 'displayName',
      nullif(v_node ->> 'roomId', '')::uuid,
      auth.uid()
    )
    on conflict (building_id, floor_id, display_name) do update
      set label_text = excluded.label_text,
          kind       = excluded.kind,
          aliases    = excluded.aliases,
          room_id    = coalesce(excluded.room_id, public.landmarks.room_id)
    returning id into v_id;

    v_refs := v_refs || jsonb_build_object(v_node ->> 'ref', v_id::text);
    v_nodes := v_nodes || jsonb_build_array(
      jsonb_set(v_node, '{ref}', to_jsonb(v_id::text))
    );
  end loop;

  -- An edge whose ends did not resolve is dropped rather than stored pointing
  -- at a ref no landmark answers to: that is what leaves an unroutable node on
  -- the map.
  for v_edge in select * from jsonb_array_elements(
                   coalesce(p_plan -> 'edges', '[]'::jsonb))
  loop
    v_from := v_refs ->> (v_edge ->> 'fromRef');
    v_to   := v_refs ->> (v_edge ->> 'toRef');
    if v_from is not null and v_to is not null and v_from <> v_to then
      v_edges := v_edges || jsonb_build_array(
        jsonb_build_object('fromRef', v_from, 'toRef', v_to)
      );
    end if;
  end loop;

  v_result := jsonb_build_object(
    'buildingId', v_building,
    'nodes', v_nodes,
    'edges', v_edges
  );

  insert into public.traced_plans (building_id, plan, traced_by)
  values (v_building, v_result, auth.uid())
  on conflict (building_id) do update
    set plan      = excluded.plan,
        traced_by = excluded.traced_by,
        updated_at = now();

  return v_result;
end;
$$;

grant execute on function public.save_traced_plan(jsonb) to authenticated;
