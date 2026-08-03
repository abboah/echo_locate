-- Backfill profiles for accounts created before handle_new_user() existed.
--
-- Without this, an existing user has no `profiles` row, and every table that
-- references it (saved_maps, building_contributors) rejects their writes with
-- a foreign-key violation.
--
-- Idempotent: new accounts are already covered by the trigger.

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
