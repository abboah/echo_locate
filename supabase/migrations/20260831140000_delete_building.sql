-- ---------------------------------------------------------------------------
-- Removing a building from the index.
--
-- The index is crowdsourced, so anybody can add one — which means anybody can
-- add one by mistake, or add a test entry and leave it sitting in everybody's
-- Explore list forever. There was no way to take it back out.
--
-- Deliberately **not** a plain RLS delete policy. Deleting a building cascades
-- its floors, its traced room plans, its contributor credits and everybody's
-- saved bookmarks — so the rule about who may do that is worth stating once,
-- in one place, with an error message that says why rather than a silent
-- no-op. (A `delete` filtered away by RLS returns success and removes nothing,
-- which is the failure mode this whole migration exists to avoid.)
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_building(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_creator uuid;
  v_others  int;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;

  select created_by into v_creator from public.buildings where id = p_id;
  if v_creator is null and not exists (
    select 1 from public.buildings where id = p_id
  ) then
    raise exception 'That building no longer exists.';
  end if;

  if v_creator is distinct from v_user then
    raise exception 'Only the person who added a building can remove it.';
  end if;

  -- The guard that matters. Somebody else may have spent twenty minutes
  -- tracing a floor of this building since it was added; one person's tidy-up
  -- is not a reason to delete another person's work, even from a building they
  -- created.
  select count(*) into v_others
    from public.room_plans
   where building_id = p_id
     and traced_by is not null
     and traced_by <> v_user;

  if v_others > 0 then
    raise exception
      'Somebody else has mapped a floor here, so this building cannot be '
      'removed.';
  end if;

  -- floors, room_plans, building_contributors and saved_maps all cascade.
  delete from public.buildings where id = p_id;
end;
$$;

revoke all on function public.delete_own_building(text) from public;
grant execute on function public.delete_own_building(text) to authenticated;

comment on function public.delete_own_building(text) is
  'Deletes a building the caller added, provided nobody else has traced a '
  'floor on it. Cascades floors, room plans, credits and bookmarks.';

-- ---------------------------------------------------------------------------
-- rename_building — the same "say so rather than silently do nothing" fix.
--
-- The client was issuing a bare `update ... where id = ?`. When the "buildings
-- editable by contributors" policy filtered the row away, PostgREST returned
-- success having changed nothing, so a forbidden rename looked exactly like a
-- successful one. Routing it through a function lets the refusal be an error.
-- ---------------------------------------------------------------------------
create or replace function public.rename_building(
  p_id   text,
  p_name text,
  p_area text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'A building needs a name.';
  end if;
  if not exists (select 1 from public.buildings where id = p_id) then
    raise exception 'That building no longer exists.';
  end if;
  if not public.can_edit_building(p_id) then
    raise exception 'Only somebody who has mapped this building can rename it.';
  end if;

  update public.buildings
     set name = btrim(p_name),
         area = case
                  when btrim(coalesce(p_area, '')) = '' then area
                  else btrim(p_area)
                end
   where id = p_id;
end;
$$;

revoke all on function public.rename_building(text, text, text) from public;
grant execute on function public.rename_building(text, text, text)
  to authenticated;

comment on function public.rename_building(text, text, text) is
  'Renames a building the caller may edit. Raises rather than silently '
  'changing nothing when the caller may not.';
