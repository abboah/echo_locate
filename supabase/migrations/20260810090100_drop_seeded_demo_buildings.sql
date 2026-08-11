-- Removes the invented buildings from any database `20260731090100` already
-- seeded.
--
-- That seed created eight buildings with invented mapper counts and completion
-- percentages, so Home and Explore listed a campus of buildings nobody had
-- mapped — a browsable claim the app could not back up. The seed file itself is
-- now trimmed to one, but a migration that has already run cannot un-run, so
-- the rows have to be deleted here.
--
-- KNUST Library is kept: a demonstration needs somewhere to demonstrate, and it
-- is the building the Profile developer shortcuts open.
--
-- Deletes cascade to floors, rooms, landmarks, routes and saved_maps by their
-- foreign keys, so a removed building leaves nothing pointing at it.
--
-- Anything a real contributor has since mapped is untouched: this names the
-- seven seeded ids explicitly rather than deleting by any broader rule.

delete from public.buildings
where id in (
  'engineering-block',
  'src-building',
  'great-hall',
  'cabs-block',
  'science-block',
  'kath-wing-a',
  'kumasi-city-mall'
);
