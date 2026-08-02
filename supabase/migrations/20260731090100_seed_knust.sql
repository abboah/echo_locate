-- Seed: the KNUST-area buildings the Phase 1 screens were designed against
-- (previously hardcoded in MockBuildingRepository).
--
-- Coordinates are approximate — campus buildings are offsets from the KNUST
-- centre, KATH and Kumasi City Mall are near their real positions. Replace
-- with GPS readings taken during field mapping.
--
-- Idempotent: safe to re-run.

insert into public.buildings
  (id, name, area, category, glyph, mapped_percent, lat, lng, seed_mappers)
values
  ('knust-library',     'KNUST Library',     'KNUST, Kumasi',   'campus',   'building', 94, 6.67650, -1.57130, 12),
  ('engineering-block', 'Engineering Block', 'KNUST, Kumasi',   'campus',   'door',     71, 6.67110, -1.57130,  8),
  ('src-building',      'SRC Building',      'KNUST, Kumasi',   'campus',   'home',     42, 6.66930, -1.57130,  3),
  ('great-hall',        'Great Hall',        'KNUST, Kumasi',   'campus',   'hall',     88, 6.67920, -1.57130,  6),
  ('cabs-block',        'CABS Block',        'KNUST, Kumasi',   'campus',   'building', 87, 6.67470, -1.56858,  4),
  ('science-block',     'Science Block',     'KNUST, Kumasi',   'campus',   'door',     62, 6.67470, -1.57492,  2),
  ('kath-wing-a',       'KATH — Wing A',     'Bantama, Kumasi', 'hospital', 'building', 55, 6.69750, -1.63180,  5),
  ('kumasi-city-mall',  'Kumasi City Mall',  'Asokwa, Kumasi',  'mall',     'hall',     77, 6.67840, -1.60860,  9)
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
    select * from (values
      ('knust-library', 4), ('engineering-block', 5), ('src-building', 2),
      ('great-hall', 1),    ('cabs-block', 3),        ('science-block', 2),
      ('kath-wing-a', 3),   ('kumasi-city-mall', 2)
    ) as t(id, floors)
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

-- Set the freshness labels last: inserting floors/rooms fires the triggers
-- that bump buildings.updated_at, so any values set earlier would be lost.
update public.buildings set updated_at = now()                     where id in ('knust-library', 'cabs-block', 'kumasi-city-mall');
update public.buildings set updated_at = now() - interval '1 day'  where id in ('engineering-block', 'science-block');
update public.buildings set updated_at = now() - interval '3 days' where id = 'src-building';
update public.buildings set updated_at = now() - interval '9 days' where id in ('great-hall', 'kath-wing-a');
