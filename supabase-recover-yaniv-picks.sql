-- One-time approved admin recovery for:
-- Display name: יניב המגניב כןכן מגניב
-- League name: CFEY
--
-- Safety behavior:
-- 1. Stops unless exactly one profile has the supplied display name.
-- 2. Stops unless that player belongs to exactly one league named CFEY.
-- 3. Backs up existing records and writes an audit record.
-- 4. Temporarily bypasses the lock only inside this transaction.
-- 5. Restores the lock and never deletes any data.

do $$
declare
  target_profile public.profiles;
  target_league public.leagues;
  profile_count integer;
  league_match_count integer;
  saved_group_count integer;
  saved_award_count integer;
begin
  select count(*) into profile_count
  from public.profiles
  where trim(squad_name) = 'יניב המגניב כןכן מגניב';

  if profile_count <> 1 then
    raise exception 'Safety stop: expected exactly one matching player, found %.', profile_count;
  end if;

  select * into target_profile
  from public.profiles
  where trim(squad_name) = 'יניב המגניב כןכן מגניב'
  limit 1;

  select count(*) into league_match_count
  from public.leagues l
  join public.league_members m on m.league_id = l.id
  where m.user_id = target_profile.id
    and lower(trim(l.name)) = lower('CFEY');

  if league_match_count = 1 then
    select l.* into target_league
    from public.leagues l
    join public.league_members m on m.league_id = l.id
    where m.user_id = target_profile.id
      and lower(trim(l.name)) = lower('CFEY')
    limit 1;
  else
    raise exception 'Safety stop: expected exactly one joined league named CFEY, found %.', league_match_count;
  end if;

  create table if not exists public.pundits_admin_recovery_audit (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    action text not null,
    player_id uuid not null,
    league_id uuid not null,
    previous_groups jsonb not null,
    previous_award jsonb,
    recovered_groups jsonb not null,
    recovered_award jsonb not null,
    note text not null
  );

  alter table public.pundits_admin_recovery_audit enable row level security;
  revoke all on public.pundits_admin_recovery_audit from public, anon, authenticated;

  insert into public.pundits_admin_recovery_audit (
    action,
    player_id,
    league_id,
    previous_groups,
    previous_award,
    recovered_groups,
    recovered_award,
    note
  )
  values (
    'approved_locked_prediction_recovery',
    target_profile.id,
    target_league.id,
    coalesce((
      select jsonb_agg(to_jsonb(g) order by g.group_key)
      from public.group_predictions g
      where g.user_id = target_profile.id and g.league_id = target_league.id
    ), '[]'::jsonb),
    (
      select to_jsonb(a)
      from public.award_predictions a
      where a.user_id = target_profile.id and a.league_id = target_league.id
      limit 1
    ),
    jsonb_build_object(
      'A', jsonb_build_array('Mexico', 'South Korea', 'Czechia', 'South Africa'),
      'B', jsonb_build_array('Switzerland', 'Canada', 'Bosnia and Herzegovina', 'Qatar'),
      'C', jsonb_build_array('Brazil', 'Morocco', 'Scotland', 'Haiti'),
      'D', jsonb_build_array('Turkiye', 'USA', 'Australia', 'Paraguay'),
      'E', jsonb_build_array('Germany', 'Ecuador', 'Ivory Coast', 'Curacao'),
      'F', jsonb_build_array('Netherlands', 'Japan', 'Sweden', 'Tunisia'),
      'G', jsonb_build_array('Belgium', 'Iran', 'New Zealand', 'Egypt'),
      'H', jsonb_build_array('Spain', 'Uruguay', 'Saudi Arabia', 'Cape Verde'),
      'I', jsonb_build_array('France', 'Senegal', 'Norway', 'Iraq'),
      'J', jsonb_build_array('Argentina', 'Austria', 'Algeria', 'Jordan'),
      'K', jsonb_build_array('Portugal', 'Colombia', 'Congo DR', 'Uzbekistan'),
      'L', jsonb_build_array('England', 'Croatia', 'Ghana', 'Panama')
    ),
    jsonb_build_object(
      'champion', 'Brazil',
      'top_scorer', 'Kylian Mbappe',
      'top_assister', 'Bruno Fernandes'
    ),
    'Picks supplied and approved by the tournament administrator after a confirmed silent-save failure.'
  );

  insert into public.official_results (result_type, result_key, value, updated_at)
  values ('setting', 'group_picks_locked', 'false'::jsonb, now())
  on conflict (result_type, result_key)
  do update set value = 'false'::jsonb, updated_at = now();

  insert into public.group_predictions (user_id, league_id, group_key, ordered_teams, locked_at)
  values
    (target_profile.id, target_league.id, 'A', jsonb_build_array('Mexico', 'South Korea', 'Czechia', 'South Africa'), now()),
    (target_profile.id, target_league.id, 'B', jsonb_build_array('Switzerland', 'Canada', 'Bosnia and Herzegovina', 'Qatar'), now()),
    (target_profile.id, target_league.id, 'C', jsonb_build_array('Brazil', 'Morocco', 'Scotland', 'Haiti'), now()),
    (target_profile.id, target_league.id, 'D', jsonb_build_array('Turkiye', 'USA', 'Australia', 'Paraguay'), now()),
    (target_profile.id, target_league.id, 'E', jsonb_build_array('Germany', 'Ecuador', 'Ivory Coast', 'Curacao'), now()),
    (target_profile.id, target_league.id, 'F', jsonb_build_array('Netherlands', 'Japan', 'Sweden', 'Tunisia'), now()),
    (target_profile.id, target_league.id, 'G', jsonb_build_array('Belgium', 'Iran', 'New Zealand', 'Egypt'), now()),
    (target_profile.id, target_league.id, 'H', jsonb_build_array('Spain', 'Uruguay', 'Saudi Arabia', 'Cape Verde'), now()),
    (target_profile.id, target_league.id, 'I', jsonb_build_array('France', 'Senegal', 'Norway', 'Iraq'), now()),
    (target_profile.id, target_league.id, 'J', jsonb_build_array('Argentina', 'Austria', 'Algeria', 'Jordan'), now()),
    (target_profile.id, target_league.id, 'K', jsonb_build_array('Portugal', 'Colombia', 'Congo DR', 'Uzbekistan'), now()),
    (target_profile.id, target_league.id, 'L', jsonb_build_array('England', 'Croatia', 'Ghana', 'Panama'), now())
  on conflict (user_id, league_id, group_key)
  do update set ordered_teams = excluded.ordered_teams, locked_at = now();

  insert into public.award_predictions (
    user_id, league_id, champion, top_scorer, top_assister, locked_at
  )
  values (
    target_profile.id, target_league.id, 'Brazil', 'Kylian Mbappe', 'Bruno Fernandes', now()
  )
  on conflict (user_id, league_id)
  do update set
    champion = excluded.champion,
    top_scorer = excluded.top_scorer,
    top_assister = excluded.top_assister,
    locked_at = now();

  update public.official_results
  set value = 'true'::jsonb, updated_at = now()
  where result_type = 'setting' and result_key = 'group_picks_locked';

  select count(*) into saved_group_count
  from public.group_predictions
  where user_id = target_profile.id and league_id = target_league.id;

  select count(*) into saved_award_count
  from public.award_predictions
  where user_id = target_profile.id
    and league_id = target_league.id
    and champion = 'Brazil'
    and top_scorer = 'Kylian Mbappe'
    and top_assister = 'Bruno Fernandes'
    and locked_at is not null;

  if saved_group_count <> 12 or saved_award_count <> 1 then
    raise exception 'Safety stop: verification failed. Found % groups and % matching Big Calls rows.',
      saved_group_count, saved_award_count;
  end if;

  raise notice 'Recovery prepared for player "%", league "%" (%).',
    target_profile.squad_name, target_league.name, target_league.code;
end;
$$;
