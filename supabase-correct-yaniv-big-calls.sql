-- One-time correction for Yaniv's locked Big Calls in league CFEY.
-- This overwrites the three Big Calls together, keeps an audit copy,
-- restores the global lock, and stops if the final values are not exact.

do $$
declare
  target_profile public.profiles;
  target_league public.leagues;
  profile_count integer;
  league_match_count integer;
  final_award public.award_predictions;
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

  if league_match_count <> 1 then
    raise exception 'Safety stop: expected exactly one joined league named CFEY, found %.', league_match_count;
  end if;

  select l.* into target_league
  from public.leagues l
  join public.league_members m on m.league_id = l.id
  where m.user_id = target_profile.id
    and lower(trim(l.name)) = lower('CFEY')
  limit 1;

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
    action, player_id, league_id, previous_groups, previous_award,
    recovered_groups, recovered_award, note
  )
  values (
    'approved_big_calls_correction',
    target_profile.id,
    target_league.id,
    '[]'::jsonb,
    (
      select to_jsonb(a)
      from public.award_predictions a
      where a.user_id = target_profile.id and a.league_id = target_league.id
      limit 1
    ),
    '{}'::jsonb,
    jsonb_build_object(
      'champion', 'Brazil',
      'top_scorer', 'Kylian Mbappe',
      'top_assister', 'Bruno Fernandes'
    ),
    'Corrected all three locked Big Calls together after cached old choices appeared in the app.'
  );

  insert into public.official_results (result_type, result_key, value, updated_at)
  values ('setting', 'group_picks_locked', 'false'::jsonb, now())
  on conflict (result_type, result_key)
  do update set value = 'false'::jsonb, updated_at = now();

  insert into public.award_predictions (
    user_id, league_id, champion, top_scorer, top_assister, locked_at
  )
  values (
    target_profile.id, target_league.id, 'Brazil', 'Kylian Mbappe', 'Bruno Fernandes', now()
  )
  on conflict (user_id, league_id)
  do update set
    champion = 'Brazil',
    top_scorer = 'Kylian Mbappe',
    top_assister = 'Bruno Fernandes',
    locked_at = now();

  update public.official_results
  set value = 'true'::jsonb, updated_at = now()
  where result_type = 'setting' and result_key = 'group_picks_locked';

  select * into final_award
  from public.award_predictions
  where user_id = target_profile.id and league_id = target_league.id;

  if final_award.champion is distinct from 'Brazil'
    or final_award.top_scorer is distinct from 'Kylian Mbappe'
    or final_award.top_assister is distinct from 'Bruno Fernandes'
    or final_award.locked_at is null then
    raise exception 'Safety stop: the final Big Calls verification failed.';
  end if;

  raise notice 'Big Calls corrected and locked: champion=%, scorer=%, assister=%.',
    final_award.champion, final_award.top_scorer, final_award.top_assister;
end;
$$;

select
  p.squad_name,
  l.name as league_name,
  a.champion,
  a.top_scorer,
  a.top_assister,
  a.locked_at
from public.award_predictions a
join public.profiles p on p.id = a.user_id
join public.leagues l on l.id = a.league_id
where trim(p.squad_name) = 'יניב המגניב כןכן מגניב'
  and lower(trim(l.name)) = lower('CFEY');
