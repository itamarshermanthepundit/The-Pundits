-- The Pundits: group-stage score audit.
-- Run this in Supabase SQL Editor to recheck every player's score.
--
-- This script is read-only except for temporary CTE calculations:
-- - It does not delete anything.
-- - It does not edit player picks.
-- - It does not edit official results.
--
-- Scoring checked here:
-- - 5 points for each team in the exact correct group position.

with expected_official_groups(group_key, expected_order) as (
  values
    ('A', '["Mexico","South Africa","South Korea","Czechia"]'::jsonb),
    ('B', '["Switzerland","Canada","Bosnia and Herzegovina","Qatar"]'::jsonb),
    ('C', '["Brazil","Morocco","Scotland","Haiti"]'::jsonb),
    ('D', '["USA","Australia","Paraguay","Turkiye"]'::jsonb),
    ('E', '["Germany","Ivory Coast","Ecuador","Curacao"]'::jsonb),
    ('F', '["Netherlands","Japan","Sweden","Tunisia"]'::jsonb),
    ('G', '["Belgium","Egypt","Iran","New Zealand"]'::jsonb),
    ('H', '["Spain","Cape Verde","Uruguay","Saudi Arabia"]'::jsonb),
    ('I', '["France","Norway","Senegal","Iraq"]'::jsonb),
    ('J', '["Argentina","Austria","Algeria","Jordan"]'::jsonb),
    ('K', '["Colombia","Portugal","Congo DR","Uzbekistan"]'::jsonb),
    ('L', '["England","Croatia","Ghana","Panama"]'::jsonb)
),
saved_official_groups as (
  select result_key as group_key, value as saved_order
  from public.official_results
  where result_type = 'group'
),
official_check as (
  select
    e.group_key,
    e.expected_order,
    s.saved_order,
    case when s.saved_order = e.expected_order then 'OK' else 'CHECK' end as status
  from expected_official_groups e
  left join saved_official_groups s on s.group_key = e.group_key
),
member_group_counts as (
  select
    lm.league_id,
    lm.user_id,
    count(gp.group_key)::int as saved_groups
  from public.league_members lm
  left join public.group_predictions gp
    on gp.league_id = lm.league_id
   and gp.user_id = lm.user_id
  group by lm.league_id, lm.user_id
),
slot_scores as (
  select
    gp.league_id,
    gp.user_id,
    gp.group_key,
    pick.ordinality::int as position_number,
    pick.team as picked_team,
    sog.saved_order ->> (pick.ordinality::int - 1) as actual_team,
    case
      when pick.team = sog.saved_order ->> (pick.ordinality::int - 1) then 5
      else 0
    end as points
  from public.group_predictions gp
  join saved_official_groups sog on sog.group_key = gp.group_key
  cross join lateral jsonb_array_elements_text(gp.ordered_teams)
    with ordinality as pick(team, ordinality)
),
group_scores as (
  select
    league_id,
    user_id,
    group_key,
    sum(points)::int as group_points,
    count(*) filter (where points = 5)::int as correct_positions
  from slot_scores
  group by league_id, user_id, group_key
),
player_totals as (
  select
    lm.league_id,
    lm.user_id,
    coalesce(sum(gs.group_points), 0)::int as total_points,
    coalesce(sum(gs.correct_positions), 0)::int as total_correct_positions,
    coalesce(max(mgc.saved_groups), 0)::int as saved_groups,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'A'), 0)::int as group_a,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'B'), 0)::int as group_b,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'C'), 0)::int as group_c,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'D'), 0)::int as group_d,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'E'), 0)::int as group_e,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'F'), 0)::int as group_f,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'G'), 0)::int as group_g,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'H'), 0)::int as group_h,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'I'), 0)::int as group_i,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'J'), 0)::int as group_j,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'K'), 0)::int as group_k,
    coalesce(sum(gs.group_points) filter (where gs.group_key = 'L'), 0)::int as group_l
  from public.league_members lm
  left join group_scores gs
    on gs.league_id = lm.league_id
   and gs.user_id = lm.user_id
  left join member_group_counts mgc
    on mgc.league_id = lm.league_id
   and mgc.user_id = lm.user_id
  group by lm.league_id, lm.user_id
),
leaderboard as (
  select
    l.name as league_name,
    l.code as league_code,
    p.squad_name,
    p.email,
    pt.total_points,
    pt.total_correct_positions,
    pt.saved_groups,
    case when pt.saved_groups = 12 then 'OK' else 'CHECK SAVED PICKS' end as pick_status,
    pt.group_a,
    pt.group_b,
    pt.group_c,
    pt.group_d,
    pt.group_e,
    pt.group_f,
    pt.group_g,
    pt.group_h,
    pt.group_i,
    pt.group_j,
    pt.group_k,
    pt.group_l
  from player_totals pt
  join public.leagues l on l.id = pt.league_id
  join public.profiles p on p.id = pt.user_id
)
select
  league_name,
  league_code,
  squad_name,
  email,
  total_points,
  total_correct_positions,
  saved_groups,
  pick_status,
  group_a,
  group_b,
  group_c,
  group_d,
  group_e,
  group_f,
  group_g,
  group_h,
  group_i,
  group_j,
  group_k,
  group_l
from leaderboard
order by league_name, total_points desc, total_correct_positions desc, squad_name;

-- Optional: run this second SELECT separately if you want to inspect every individual team pick.
-- It shows one row per team position and whether it got 5 points.
/*
with saved_official_groups as (
  select result_key as group_key, value as saved_order
  from public.official_results
  where result_type = 'group'
)
select
  l.name as league_name,
  p.squad_name,
  gp.group_key,
  pick.ordinality::int as position_number,
  pick.team as picked_team,
  sog.saved_order ->> (pick.ordinality::int - 1) as actual_team,
  case
    when pick.team = sog.saved_order ->> (pick.ordinality::int - 1) then 5
    else 0
  end as points
from public.group_predictions gp
join saved_official_groups sog on sog.group_key = gp.group_key
join public.leagues l on l.id = gp.league_id
join public.profiles p on p.id = gp.user_id
cross join lateral jsonb_array_elements_text(gp.ordered_teams)
  with ordinality as pick(team, ordinality)
order by l.name, p.squad_name, gp.group_key, position_number;
*/
