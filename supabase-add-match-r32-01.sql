-- The Pundits: add first knockout score-prediction match.
-- Run this in Supabase SQL Editor.
--
-- Match locks automatically at kickoff_at.
-- Time is Israel time: June 28, 2026 at 22:00.

insert into public.official_results (result_type, result_key, value, updated_at)
values (
  'match',
  'R32-01',
  '{
    "stage": "Round of 32",
    "home_team": "South Africa",
    "away_team": "Canada",
    "kickoff_at": "2026-06-28T22:00:00+03:00"
  }'::jsonb,
  now()
)
on conflict (result_type, result_key)
do update set
  value = excluded.value,
  updated_at = now();

select
  result_key as match_key,
  value->>'stage' as stage,
  value->>'home_team' as home_team,
  value->>'away_team' as away_team,
  value->>'kickoff_at' as locks_at_israel_time
from public.official_results
where result_type = 'match'
  and result_key = 'R32-01';
