-- ---------------------------------------------------------------------------
-- Account management and problem reports.
--
-- The Profile tab had no way to change a name, no way to leave, and no way to
-- tell anybody something was broken. The first two are ordinary account
-- expectations; the third matters more than usual here, because the people
-- this app is built for are the least able to demonstrate a fault by pointing
-- at the screen.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- feedback — problem reports and suggestions from inside the app.
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete set null,
  kind        text not null default 'problem'
                check (kind in ('problem', 'idea', 'map_error')),
  message     text not null check (length(btrim(message)) > 0),
  -- Where the user was when they hit it. Optional, and the reason a report is
  -- worth more than an email: "the route was wrong" is unactionable without
  -- knowing which floor of which building.
  building_id text references public.buildings (id) on delete set null,
  floor_id    uuid references public.floors (id) on delete set null,
  -- Free-form device/build string, so a fault can be tied to a version.
  context     text not null default '',
  created_at  timestamptz not null default now()
);

comment on table public.feedback is
  'In-app problem reports. user_id is nulled rather than cascaded on account '
  'deletion so a report survives the reporter leaving.';

create index if not exists feedback_user_idx on public.feedback (user_id);
create index if not exists feedback_created_idx on public.feedback (created_at desc);

alter table public.feedback enable row level security;

-- Anyone signed in can file one, against their own id and nobody else's.
drop policy if exists "feedback insertable by author" on public.feedback;
create policy "feedback insertable by author"
  on public.feedback for insert to authenticated
  with check (user_id = auth.uid());

-- And read back only their own.
drop policy if exists "feedback readable by author" on public.feedback;
create policy "feedback readable by author"
  on public.feedback for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- delete_own_account — leaving, and taking your identity with you.
--
-- `security definer` because deleting from `auth.users` is not something a
-- signed-in role may do directly. It deletes exactly one row — the caller's —
-- and `auth.uid()` cannot be forged from the client, so there is no id
-- parameter to abuse.
--
-- **What survives.** `profiles` cascades and goes. Traced floor plans and the
-- buildings they belong to do NOT: they are the crowdsourced map other people
-- are relying on, and deleting an account is not a reason to unmap a building
-- for everybody else. `room_plans.traced_by` and `feedback.user_id` are set
-- null instead, so the work stays and the attribution does not. The UI says
-- this before it asks.
-- ---------------------------------------------------------------------------
create or replace function public.delete_own_account()
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

  -- Keep the map, drop the link to the person.
  update public.room_plans set traced_by = null where traced_by = v_user;
  update public.feedback    set user_id   = null where user_id   = v_user;
  delete from public.building_contributors where user_id = v_user;
  delete from public.saved_maps where user_id = v_user;

  -- profiles cascades from this.
  delete from auth.users where id = v_user;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;

comment on function public.delete_own_account() is
  'Deletes the calling user''s account. Traced plans and buildings are kept '
  'for the crowdsourced map; attribution is nulled.';
