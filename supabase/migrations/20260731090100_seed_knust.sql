-- Seed: the one building kept for demonstration.
--
-- This file used to seed eight invented buildings with invented mapper counts
-- and completion percentages. They were Phase 1 scaffolding for screens built
-- before there was a database, and they became misleading the moment there was
-- one: a browsable campus of buildings nobody has actually mapped.
--
-- KNUST Library survives alone, because a demo needs somewhere to demo. Its
-- floors and rooms are real enough to trace against, and `20260810090100`
-- removes the other seven from any database this already ran on.
--
-- Coordinates are approximate. Replace with a GPS reading taken on site.
--
-- Idempotent: safe to re-run.

insert into public.buildings
  (id, name, area, category, glyph, mapped_percent, lat, lng, seed_mappers)
values
  ('knust-library', 'KNUST Library', 'KNUST, Kumasi', 'campus', 'building', 94, 6.67650, -1.57130, 12)
on conflict (id) do update set
  name           = excluded.name,
  area           = excluded.area,
  category       = excluded.category,
  glyph          = excluded.glyph,
  mapped_percent = excluded.mapped_percent,
  lat            = excluded.lat,
  lng            = excluded.lng,
  seed_mappers   = excluded.seed_mappers;

-- Floors + rooms. Floor counts match the design; room names follow the same
-- pattern the mock repository used, except KNUST Library floor 2, which is
-- the floor drawn in the Building Detail screen (Figma 7:301).
do $$
declare
  b            record;
  floor_count  int;
  i            int;
  floor_label  text;
  new_floor_id uuid;
begin
  for b in
    select * from (values ('knust-library', 4)) as t(id, floors)
  loop
    floor_count := b.floors;

    for i in 0 .. floor_count - 1 loop
      floor_label := case when i = 0 then 'G' else i::text end;

      insert into public.floors (building_id, label, ordinal)
      values (b.id, floor_label, i)
      on conflict (building_id, ordinal) do update set label = excluded.label
      returning id into new_floor_id;

      -- Re-seeding replaces a floor's rooms rather than duplicating them.
      delete from public.rooms where floor_id = new_floor_id;

      if b.id = 'knust-library' and i = 2 then
        insert into public.rooms (floor_id, name, kind, distance_m) values
          (new_floor_id, 'Reading Hall',   'hall', 40),
          (new_floor_id, 'Study Room 2B',  'room', 65),
          (new_floor_id, 'Help Desk',      'desk', 20);
      else
        insert into public.rooms (floor_id, name, kind, distance_m) values
          (new_floor_id, 'Room ' || floor_label || '01', 'room', 25),
          (new_floor_id, 'Room ' || floor_label || '02', 'room', 45),
          (new_floor_id, 'Washroom',                     'desk', 30);
      end if;
    end loop;
  end loop;
end $$;

-- Set the freshness label last: inserting floors/rooms fires the triggers that
-- bump buildings.updated_at, so a value set earlier would be lost.
update public.buildings set updated_at = now() where id = 'knust-library';
