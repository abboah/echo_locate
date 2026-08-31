-- The photograph a traced plan was made from, and the ability to undo a trace.
--
-- Until now the plan photo lived only on the device that took it: a second
-- contributor opening the building saw the landmarks floating over a blank
-- grid, and nobody could check a trace against the board it came from. The
-- graph is the taps, but the photo is the evidence.

-- ---------------------------------------------------------------------------
-- Bucket
-- ---------------------------------------------------------------------------
-- Public read. What is stored here is a photograph of a sign screwed to a
-- public wall — the same thing anyone walking past can see — and making it
-- public means the map draws without minting a signed URL per tile. Nothing
-- private is ever uploaded here; that is enforced by the write policy below,
-- which only lets a building's own contributors put a file in its folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'plan-photos',
  'plan-photos',
  true,
  10485760,                                  -- 10 MB: a full-resolution plan
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Objects are keyed `<building_id>/<floor_id>.jpg`, so the first path segment
-- names the building whose contributors may write there.
drop policy if exists plan_photos_read on storage.objects;
create policy plan_photos_read
  on storage.objects for select
  using (bucket_id = 'plan-photos');

drop policy if exists plan_photos_write on storage.objects;
create policy plan_photos_write
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'plan-photos'
    and public.can_edit_building((storage.foldername(name))[1])
  );

drop policy if exists plan_photos_update on storage.objects;
create policy plan_photos_update
  on storage.objects for update to authenticated
  using (
    bucket_id = 'plan-photos'
    and public.can_edit_building((storage.foldername(name))[1])
  );

drop policy if exists plan_photos_delete on storage.objects;
create policy plan_photos_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'plan-photos'
    and public.can_edit_building((storage.foldername(name))[1])
  );

-- ---------------------------------------------------------------------------
-- Where the plan's photos live, per floor
-- ---------------------------------------------------------------------------
-- A map rather than a single column: a plan spans floors, and each floor has
-- its own board on its own wall. Kept beside the plan rather than inside its
-- `plan` jsonb so that re-saving a trace cannot drop the photos, and so a
-- photo can be replaced without rewriting the graph.
alter table public.traced_plans
  add column if not exists photo_urls jsonb not null default '{}'::jsonb;

comment on column public.traced_plans.photo_urls is
  'floor_id -> public URL of the plan photograph that floor was traced from.';

-- ---------------------------------------------------------------------------
-- Recording a floor's photo without touching the graph
-- ---------------------------------------------------------------------------
create or replace function public.set_plan_photo(
  p_building_id text,
  p_floor_id    text,
  p_url         text
)
returns jsonb
language plpgsql
security invoker
set search_path = public as $$
declare
  v_urls jsonb;
begin
  if not public.can_edit_building(p_building_id) then
    raise exception 'set_plan_photo: not a contributor to %', p_building_id;
  end if;

  -- A photo can arrive before the first save (the contributor shoots the board,
  -- then traces), so this must not depend on a row already existing. An empty
  -- plan is a legitimate intermediate state; `save_traced_plan` fills it in.
  insert into public.traced_plans (building_id, plan, traced_by, photo_urls)
  values (
    p_building_id,
    jsonb_build_object('buildingId', p_building_id, 'nodes', '[]'::jsonb,
                       'edges', '[]'::jsonb),
    auth.uid(),
    jsonb_build_object(p_floor_id, p_url)
  )
  on conflict (building_id) do update
    set photo_urls = public.traced_plans.photo_urls
                     || jsonb_build_object(p_floor_id, p_url),
        updated_at = now()
  returning photo_urls into v_urls;

  return v_urls;
end;
$$;

grant execute on function public.set_plan_photo(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Undoing a trace
-- ---------------------------------------------------------------------------
-- Deletes the plan and forgets its photos. **Landmarks are deliberately left
-- standing**: recorded walking routes reference them by id, so removing them
-- would break every route through the building, and a landmark nobody
-- references costs a row. Re-tracing the building overwrites the plan anyway.
--
-- Returns the photo paths so the client can delete the objects themselves —
-- storage has no foreign keys, and a row deleted without its files leaves the
-- bucket growing for nothing.
create or replace function public.delete_traced_plan(p_building_id text)
returns jsonb
language plpgsql
security invoker
set search_path = public as $$
declare
  v_urls jsonb;
begin
  if not public.can_edit_building(p_building_id) then
    raise exception 'delete_traced_plan: not a contributor to %', p_building_id;
  end if;

  select photo_urls into v_urls
    from public.traced_plans
   where building_id = p_building_id;

  delete from public.traced_plans where building_id = p_building_id;

  return coalesce(v_urls, '{}'::jsonb);
end;
$$;

grant execute on function public.delete_traced_plan(text) to authenticated;
