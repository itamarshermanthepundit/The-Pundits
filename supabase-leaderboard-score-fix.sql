-- The Pundits: include locked group-stage points in league leaderboard data.
-- Safe: this does not edit or delete any player picks.

create or replace function public.get_league_entries_with_code(
  p_access_code text,
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid;
  public_picks boolean :=
    now() >= '2026-06-11 22:00:00+03'::timestamptz
    or exists (
      select 1 from public.official_results
      where result_type = 'setting' and result_key = 'group_picks_locked' and value = 'true'::jsonb
    );
  members_json jsonb;
  groups_json jsonb;
  awards_json jsonb;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    raise exception 'Player account not found.';
  end if;

  if not exists (
    select 1 from public.league_members m
    where m.league_id = p_league_id and m.user_id = player_id
  ) then
    raise exception 'Join this league before viewing it.';
  end if;

  with official_groups as (
    select result_key as group_key, value as final_order
    from public.official_results
    where result_type = 'group'
  ),
  slot_scores as (
    select
      gp.league_id,
      gp.user_id,
      case
        when pick.team = og.final_order ->> (pick.ordinality::int - 1) then 5
        else 0
      end as points
    from public.group_predictions gp
    join official_groups og on og.group_key = gp.group_key
    cross join lateral jsonb_array_elements_text(gp.ordered_teams)
      with ordinality as pick(team, ordinality)
    where gp.league_id = p_league_id
  ),
  member_scores as (
    select
      lm.user_id,
      coalesce(sum(ss.points), 0)::int as group_stage_points,
      coalesce(count(*) filter (where ss.points = 5), 0)::int as correct_positions
    from public.league_members lm
    left join slot_scores ss
      on ss.league_id = lm.league_id
     and ss.user_id = lm.user_id
    where lm.league_id = p_league_id
    group by lm.user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'profiles', jsonb_build_object('email', p.email, 'squad_name', p.squad_name),
    'group_stage_points', coalesce(ms.group_stage_points, 0),
    'correct_positions', coalesce(ms.correct_positions, 0)
  ) order by coalesce(ms.group_stage_points, 0) desc, coalesce(ms.correct_positions, 0) desc, p.squad_name), '[]'::jsonb)
  into members_json
  from public.league_members m
  join public.profiles p on p.id = m.user_id
  left join member_scores ms on ms.user_id = m.user_id
  where m.league_id = p_league_id;

  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb) into groups_json
  from public.group_predictions g
  where g.league_id = p_league_id and (public_picks or g.user_id = player_id);

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into awards_json
  from public.award_predictions a
  where a.league_id = p_league_id and (public_picks or a.user_id = player_id);

  return jsonb_build_object(
    'members', members_json,
    'groups', groups_json,
    'awards', awards_json,
    'picksArePublic', public_picks
  );
end;
$$;

grant execute on function public.get_league_entries_with_code(text, uuid) to anon, authenticated;

select
  member->'profiles'->>'squad_name' as squad_name,
  member->>'group_stage_points' as group_stage_points,
  member->>'correct_positions' as correct_positions
from jsonb_array_elements(public.get_league_entries_with_code(
  (select access_code from public.profiles where lower(email) = lower('itamarsherman@gmail.com') limit 1),
  (select id from public.leagues where code = 'WC26-4052' limit 1)
)->'members') as member
order by (member->>'group_stage_points')::int desc, squad_name;