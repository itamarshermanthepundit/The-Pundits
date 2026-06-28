-- The Pundits: enter official group-stage results and calculate points.
-- Run this once in Supabase SQL Editor.
--
-- Safety:
-- - Does not delete player picks.
-- - Does not edit player picks.
-- - Only upserts official group result rows in public.official_results.
-- - Final SELECT returns every league member with their group-stage score.
--
-- Scoring:
-- - 5 points for each team predicted in its exact final group position.

insert into public.official_results (result_type, result_key, value, updated_at)
values
  ('group', 'A', '["Mexico","South Africa","South Korea","Czechia"]'::jsonb, now()),
  ('group', 'B', '["Switzerland","Canada","Bosnia and Herzegovina","Qatar"]'::jsonb, now()),
  ('group', 'C', '["Brazil","Morocco","Scotland","Haiti"]'::jsonb, now()),
  ('group', 'D', '["USA","Australia","Paraguay","Turkiye"]'::jsonb, now()),
  ('group', 'E', '["Germany","Ivory Coast","Ecuador","Curacao"]'::jsonb, now()),
  ('group', 'F', '["Netherlands","Japan","Sweden","Tunisia"]'::jsonb, now()),
  ('group', 'G', '["Belgium","Egypt","Iran","New Zealand"]'::jsonb, now()),
  ('group', 'H', '["Spain","Cape Verde","Uruguay","Saudi Arabia"]'::jsonb, now()),
  ('group', 'I', '["France","Norway","Senegal","Iraq"]'::jsonb, now()),
  ('group', 'J', '["Argentina","Austria","Algeria","Jordan"]'::jsonb, now()),
  ('group', 'K', '["Colombia","Portugal","Congo DR","Uzbekistan"]'::jsonb, now()),
  ('group', 'L', '["England","Croatia","Ghana","Panama"]'::jsonb, now())
on conflict (result_type, result_key)
do update set value = excluded.value, updated_at = now();

insert into public.official_results (result_type, result_key, value, updated_at)
values ('setting', 'group_stage_scored', 'true'::jsonb, now())
on conflict (result_type, result_key)
do update set value = excluded.value, updated_at = now();

with official_groups as (
  select result_key as group_key, value as final_order
  from public.official_results
  where result_type = 'group'
),
slot_scores as (
  select
    gp.league_id,
    gp.user_id,
    gp.group_key,
    pick.ordinality::int as position_number,
    pick.team as picked_team,
    og.final_order ->> (pick.ordinality::int - 1) as actual_team,
    case
      when pick.team = og.final_order ->> (pick.ordinality::int - 1) then 5
      else 0
    end as points
  from public.group_predictions gp
  join official_groups og on og.group_key = gp.group_key
  cross join lateral jsonb_array_elements_text(gp.ordered_teams)
    with ordinality as pick(team, ordinality)
),
member_scores as (
  select
    lm.league_id,
    lm.user_id,
    coalesce(sum(ss.points), 0)::int as group_stage_points,
    coalesce(count(*) filter (where ss.points = 5), 0)::int as correct_positions
  from public.league_members lm
  left join slot_scores ss
    on ss.league_id = lm.league_id
   and ss.user_id = lm.user_id
  group by lm.league_id, lm.user_id
)
select
  l.name as league_name,
  l.code as league_code,
  p.squad_name,
  p.email,
  ms.group_stage_points,
  ms.correct_positions
from member_scores ms
join public.leagues l on l.id = ms.league_id
join public.profiles p on p.id = ms.user_id
order by
  l.name,
  ms.group_stage_points desc,
  ms.correct_positions desc,
  p.squad_name;
