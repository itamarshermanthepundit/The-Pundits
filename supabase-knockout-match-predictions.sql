-- The Pundits: knockout match prediction support.
-- Run this once in Supabase SQL Editor.
--
-- What it adds:
-- - Code-login users can save exact-score predictions for each match.
-- - A match locks automatically at kickoff_at.
-- - League members can see everyone else's predictions only after that match has kicked off.
--
-- Match setup:
-- Add matches as official_results rows with result_type = 'match'.
-- Example:
-- insert into public.official_results (result_type, result_key, value)
-- values (
--   'match',
--   'R32-01',
--   '{"stage":"Round of 32","home_team":"Mexico","away_team":"South Korea","kickoff_at":"2026-06-29T20:00:00+03:00"}'::jsonb
-- )
-- on conflict (result_type, result_key)
-- do update set value = excluded.value, updated_at = now();

create or replace function public.get_bracket_predictions_with_code(
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
  matches_json jsonb;
  own_json jsonb;
  revealed_json jsonb;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    raise exception 'Pundit code not found.';
  end if;

  if not exists (
    select 1 from public.league_members m
    where m.league_id = p_league_id and m.user_id = player_id
  ) then
    raise exception 'Join this league before predicting knockout matches.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'match_key', r.result_key,
    'stage', coalesce(r.value->>'stage', 'Knockout'),
    'home_team', coalesce(r.value->>'home_team', r.value->>'home'),
    'away_team', coalesce(r.value->>'away_team', r.value->>'away'),
    'kickoff_at', r.value->>'kickoff_at',
    'venue', r.value->>'venue'
  ) order by (r.value->>'kickoff_at')::timestamptz nulls last, r.result_key), '[]'::jsonb)
  into matches_json
  from public.official_results r
  where r.result_type = 'match';

  select coalesce(jsonb_agg(to_jsonb(bp)), '[]'::jsonb)
  into own_json
  from public.bracket_predictions bp
  where bp.league_id = p_league_id
    and bp.user_id = player_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'match_key', bp.match_key,
    'user_id', bp.user_id,
    'squad_name', p.squad_name,
    'picked_winner', bp.picked_winner,
    'predicted_home_score', bp.predicted_home_score,
    'predicted_away_score', bp.predicted_away_score,
    'locked_at', bp.locked_at
  ) order by bp.match_key, p.squad_name), '[]'::jsonb)
  into revealed_json
  from public.bracket_predictions bp
  join public.profiles p on p.id = bp.user_id
  join public.official_results r
    on r.result_type = 'match'
   and r.result_key = bp.match_key
  where bp.league_id = p_league_id
    and (r.value->>'kickoff_at')::timestamptz <= now();

  return jsonb_build_object(
    'matches', matches_json,
    'ownPredictions', own_json,
    'revealedPredictions', revealed_json
  );
end;
$$;

grant execute on function public.get_bracket_predictions_with_code(text, uuid) to anon, authenticated;

create or replace function public.save_bracket_prediction_with_code(
  p_access_code text,
  p_league_id uuid,
  p_match_key text,
  p_home_score integer,
  p_away_score integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid;
  match_row public.official_results;
  kickoff_at timestamptz;
  home_team text;
  away_team text;
  winner text;
  saved public.bracket_predictions;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    raise exception 'Pundit code not found.';
  end if;

  if not exists (
    select 1 from public.league_members m
    where m.league_id = p_league_id and m.user_id = player_id
  ) then
    raise exception 'Join this league before predicting knockout matches.';
  end if;

  select * into match_row
  from public.official_results r
  where r.result_type = 'match'
    and r.result_key = p_match_key
  limit 1;

  if match_row.id is null then
    raise exception 'This match is not open yet.';
  end if;

  kickoff_at := (match_row.value->>'kickoff_at')::timestamptz;
  home_team := coalesce(match_row.value->>'home_team', match_row.value->>'home');
  away_team := coalesce(match_row.value->>'away_team', match_row.value->>'away');

  if kickoff_at is null then
    raise exception 'This match does not have a kickoff time yet.';
  end if;

  if now() >= kickoff_at then
    raise exception 'This match has kicked off. Predictions are locked.';
  end if;

  if p_home_score is null or p_away_score is null or p_home_score < 0 or p_away_score < 0 then
    raise exception 'Enter a valid score for both teams.';
  end if;

  if p_home_score = p_away_score then
    raise exception 'Pick a winning score. Knockout predictions cannot be draws.';
  end if;

  winner := case when p_home_score > p_away_score then home_team else away_team end;

  insert into public.bracket_predictions (
    user_id,
    league_id,
    match_key,
    picked_winner,
    predicted_home_score,
    predicted_away_score,
    locked_at
  )
  values (
    player_id,
    p_league_id,
    p_match_key,
    winner,
    p_home_score,
    p_away_score,
    null
  )
  on conflict (user_id, league_id, match_key)
  do update set
    picked_winner = excluded.picked_winner,
    predicted_home_score = excluded.predicted_home_score,
    predicted_away_score = excluded.predicted_away_score,
    locked_at = null
  returning * into saved;

  return to_jsonb(saved);
end;
$$;

grant execute on function public.save_bracket_prediction_with_code(text, uuid, text, integer, integer) to anon, authenticated;
