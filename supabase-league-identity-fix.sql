-- The Pundits league identity and visibility repair.
-- Run this once in the Supabase SQL Editor after the previous upgrades.

create or replace function public.sync_authenticated_profile(p_squad_name text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  current_id uuid := auth.uid();
  current_email text := lower(coalesce(auth.jwt()->>'email', ''));
  duplicate_profile public.profiles;
  saved_profile public.profiles;
  kept_code text;
begin
  if current_id is null or current_email = '' then
    raise exception 'Sign in first.';
  end if;

  select * into duplicate_profile
  from public.profiles
  where lower(email) = current_email and id <> current_id
  order by (access_code is not null) desc, created_at asc
  limit 1;

  kept_code := duplicate_profile.access_code;
  if kept_code is not null then
    update public.profiles set access_code = null where id = duplicate_profile.id;
  end if;

  insert into public.profiles (id, email, squad_name, access_code, is_admin)
  values (
    current_id,
    current_email,
    coalesce(nullif(p_squad_name, ''), nullif(duplicate_profile.squad_name, ''), split_part(current_email, '@', 1)),
    kept_code,
    current_email = 'itamarsherman@gmail.com'
  )
  on conflict (id) do update set
    email = excluded.email,
    squad_name = coalesce(nullif(p_squad_name, ''), public.profiles.squad_name),
    access_code = coalesce(public.profiles.access_code, excluded.access_code),
    is_admin = public.profiles.is_admin or excluded.is_admin
  returning * into saved_profile;

  if duplicate_profile.id is not null then
    insert into public.league_members (league_id, user_id, joined_at)
    select league_id, current_id, joined_at
    from public.league_members
    where user_id = duplicate_profile.id
    on conflict (league_id, user_id) do nothing;

    update public.leagues set owner_id = current_id where owner_id = duplicate_profile.id;

    insert into public.group_predictions (user_id, league_id, group_key, ordered_teams, locked_at)
    select current_id, league_id, group_key, ordered_teams, locked_at
    from public.group_predictions where user_id = duplicate_profile.id
    on conflict (user_id, league_id, group_key) do update
      set ordered_teams = excluded.ordered_teams,
          locked_at = coalesce(public.group_predictions.locked_at, excluded.locked_at);

    insert into public.award_predictions (user_id, league_id, champion, top_scorer, top_assister, locked_at)
    select current_id, league_id, champion, top_scorer, top_assister, locked_at
    from public.award_predictions where user_id = duplicate_profile.id
    on conflict (user_id, league_id) do update
      set champion = coalesce(public.award_predictions.champion, excluded.champion),
          top_scorer = coalesce(public.award_predictions.top_scorer, excluded.top_scorer),
          top_assister = coalesce(public.award_predictions.top_assister, excluded.top_assister),
          locked_at = coalesce(public.award_predictions.locked_at, excluded.locked_at);

    insert into public.bracket_predictions (
      user_id, league_id, match_key, picked_winner, predicted_home_score, predicted_away_score, locked_at
    )
    select current_id, league_id, match_key, picked_winner, predicted_home_score, predicted_away_score, locked_at
    from public.bracket_predictions where user_id = duplicate_profile.id
    on conflict (user_id, league_id, match_key) do update
      set picked_winner = coalesce(public.bracket_predictions.picked_winner, excluded.picked_winner),
          predicted_home_score = coalesce(public.bracket_predictions.predicted_home_score, excluded.predicted_home_score),
          predicted_away_score = coalesce(public.bracket_predictions.predicted_away_score, excluded.predicted_away_score),
          locked_at = coalesce(public.bracket_predictions.locked_at, excluded.locked_at);

    update public.official_results set updated_by = current_id where updated_by = duplicate_profile.id;
    delete from public.profiles where id = duplicate_profile.id;
  end if;

  return saved_profile;
end;
$$;

grant execute on function public.sync_authenticated_profile(text) to authenticated;

create or replace function public.get_league_entries_for_user(p_league_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid := auth.uid();
  public_picks boolean := now() >= '2026-06-11 22:00:00+03'::timestamptz;
  members_json jsonb;
  groups_json jsonb;
  awards_json jsonb;
begin
  if player_id is null then raise exception 'Sign in first.'; end if;
  if not exists (
    select 1 from public.league_members where league_id = p_league_id and user_id = player_id
  ) then raise exception 'Join this league first.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'profiles', jsonb_build_object('email', p.email, 'squad_name', p.squad_name)
  ) order by p.squad_name), '[]'::jsonb)
  into members_json
  from public.league_members m
  join public.profiles p on p.id = m.user_id
  where m.league_id = p_league_id;

  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb) into groups_json
  from public.group_predictions g
  where g.league_id = p_league_id and (public_picks or g.user_id = player_id);

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into awards_json
  from public.award_predictions a
  where a.league_id = p_league_id and (public_picks or a.user_id = player_id);

  return jsonb_build_object(
    'members', members_json, 'groups', groups_json, 'awards', awards_json, 'picksArePublic', public_picks
  );
end;
$$;

grant execute on function public.get_league_entries_for_user(uuid) to authenticated;

-- Make code profiles reuse an existing email identity instead of creating a duplicate.
create or replace function public.upsert_code_profile(
  p_access_code text,
  p_email text,
  p_squad_name text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := upper(trim(p_access_code));
  clean_email text := lower(trim(p_email));
  found_profile public.profiles;
begin
  if clean_code = '' then raise exception 'Pundit code is required.'; end if;

  select * into found_profile from public.profiles
  where upper(access_code) = clean_code
  limit 1;

  if found_profile.id is null and clean_email <> '' then
    select * into found_profile from public.profiles
    where lower(email) = clean_email
    order by created_at asc
    limit 1;
  end if;

  if found_profile.id is null then
    insert into public.profiles (id, email, squad_name, access_code)
    values (
      gen_random_uuid(),
      coalesce(nullif(clean_email, ''), clean_code || '@thepundits.local'),
      coalesce(nullif(p_squad_name, ''), 'New Pundit'),
      clean_code
    ) returning * into found_profile;
  else
    update public.profiles
    set email = coalesce(nullif(clean_email, ''), found_profile.email),
        squad_name = coalesce(nullif(p_squad_name, ''), found_profile.squad_name),
        access_code = coalesce(found_profile.access_code, clean_code)
    where id = found_profile.id
    returning * into found_profile;
  end if;
  return found_profile;
end;
$$;

grant execute on function public.upsert_code_profile(text, text, text) to anon, authenticated;

drop function if exists public.get_admin_app_stats();
create or replace function public.get_admin_app_stats(p_access_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_allowed boolean := false;
begin
  admin_allowed :=
    lower(coalesce(auth.jwt()->>'email', '')) = 'itamarsherman@gmail.com'
    or exists (
      select 1
      from public.profiles
      where lower(email) = 'itamarsherman@gmail.com'
        and upper(access_code) = upper(nullif(trim(p_access_code), ''))
    );

  if not admin_allowed then
    raise exception 'Admin access required.';
  end if;

  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'leagues', (select count(*) from public.leagues),
    'memberships', (select count(*) from public.league_members)
  );
end;
$$;

revoke all on function public.get_admin_app_stats(text) from public;
grant execute on function public.get_admin_app_stats(text) to anon, authenticated;
