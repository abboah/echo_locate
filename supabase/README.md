# Supabase — EchoLocate v2

All database schema lives here as ordered migrations. Nothing is applied by
hand in the dashboard: if it isn't in `migrations/`, it doesn't exist.

| File | What it does |
|---|---|
| `migrations/20260731090000_init_schema.sql` | Tables, `buildings_view`, RPCs, triggers, RLS policies |
| `migrations/20260731090100_seed_knust.sql` | The KNUST buildings/floors/rooms the Phase 1 screens were designed against |

Project ref: `aduhafqoovyxvwkvotzo`.

## Applying migrations

```bash
supabase login                              # once, opens a browser
supabase link --project-ref aduhafqoovyxvwkvotzo   # asks for the database password
supabase db push                            # applies anything not yet applied
```

## Testing changes locally first (needs Docker running)

```bash
supabase db start     # spins up Postgres and applies every migration in order
supabase db reset     # re-applies from scratch — the fastest way to catch SQL errors
supabase stop
```

## Adding a migration

```bash
supabase migration new <name>   # creates a timestamped file in migrations/
```

Write it so re-running is safe (`on conflict do update`, `create or replace`),
then `supabase db push`.

## How the app reads this

`SupabaseBuildingRepository` and `SupabaseProfileRepository` (in
`lib/features/…`) are the only places that know the column names. They swap in
for the mock repositories automatically when `.env` has `SUPABASE_URL` and
`SUPABASE_KEY` — see `AppConfig.hasSupabase` and `injection_container.dart`.

Derived values the UI shows — floor count, mapper count, "updated today",
distance in km — are computed in `buildings_view` and the RPCs, never stored,
so they can't drift from the underlying rows.

### RPCs

| Function | Used by |
|---|---|
| `nearby_buildings(lat, lng, category, query)` | Explore — filter chips + search, sorted by distance |
| `recently_mapped_buildings(limit)` | Home — the caller's own contributions, falling back to the newest buildings for accounts with none |
| `contributor_stats()` | Profile — buildings/floors/rooms mapped |

`seed_mappers` on `buildings` exists only so demo rows don't all read
"0 mappers"; buildings created in-app leave it at 0 and the count comes
entirely from `building_contributors`.
