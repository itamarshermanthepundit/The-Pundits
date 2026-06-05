-- The Pundits dashboard upgrade.
-- Run this once in Supabase SQL Editor after the original schema.

drop policy if exists "leagues visible to members" on public.leagues;
drop policy if exists "authenticated users can find leagues" on public.leagues;
create policy "authenticated users can find leagues"
  on public.leagues for select to authenticated using (true);

insert into public.league_members (league_id, user_id)
select l.id, l.owner_id
from public.leagues l
where not exists (
  select 1 from public.league_members m
  where m.league_id = l.id and m.user_id = l.owner_id
);

create or replace function public.join_league_by_code(join_code text)
returns public.leagues
language plpgsql
security definer
set search_path = public
as $$
declare
  found_league public.leagues;
begin
  select *
  into found_league
  from public.leagues
  where upper(code) = upper(join_code)
  limit 1;

  if found_league.id is null then
    raise exception 'League code not found.';
  end if;

  insert into public.league_members (league_id, user_id)
  values (found_league.id, auth.uid())
  on conflict (league_id, user_id) do nothing;

  return found_league;
end;
$$;

grant execute on function public.join_league_by_code(text) to authenticated;

drop policy if exists "users can leave leagues" on public.league_members;
create policy "users can leave leagues"
  on public.league_members for delete to authenticated using (user_id = auth.uid());

drop policy if exists "users manage own group predictions" on public.group_predictions;
drop policy if exists "league members can view group predictions" on public.group_predictions;
drop policy if exists "users can insert own group predictions" on public.group_predictions;
drop policy if exists "users can update own group predictions" on public.group_predictions;
drop policy if exists "users can delete own group predictions" on public.group_predictions;
create policy "league members can view group predictions"
  on public.group_predictions for select to authenticated
  using (exists (
    select 1 from public.league_members m
    where m.league_id = group_predictions.league_id and m.user_id = auth.uid()
  ));
create policy "users can insert own group predictions"
  on public.group_predictions for insert to authenticated with check (user_id = auth.uid());
create policy "users can update own group predictions"
  on public.group_predictions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users can delete own group predictions"
  on public.group_predictions for delete to authenticated using (user_id = auth.uid());

drop policy if exists "users manage own award predictions" on public.award_predictions;
drop policy if exists "league members can view award predictions" on public.award_predictions;
drop policy if exists "users can insert own award predictions" on public.award_predictions;
drop policy if exists "users can update own award predictions" on public.award_predictions;
drop policy if exists "users can delete own award predictions" on public.award_predictions;
create policy "league members can view award predictions"
  on public.award_predictions for select to authenticated
  using (exists (
    select 1 from public.league_members m
    where m.league_id = award_predictions.league_id and m.user_id = auth.uid()
  ));
create policy "users can insert own award predictions"
  on public.award_predictions for insert to authenticated with check (user_id = auth.uid());
create policy "users can update own award predictions"
  on public.award_predictions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users can delete own award predictions"
  on public.award_predictions for delete to authenticated using (user_id = auth.uid());

drop policy if exists "users manage own bracket predictions" on public.bracket_predictions;
drop policy if exists "league members can view bracket predictions" on public.bracket_predictions;
drop policy if exists "users can insert own bracket predictions" on public.bracket_predictions;
drop policy if exists "users can update own bracket predictions" on public.bracket_predictions;
drop policy if exists "users can delete own bracket predictions" on public.bracket_predictions;
create policy "league members can view bracket predictions"
  on public.bracket_predictions for select to authenticated
  using (exists (
    select 1 from public.league_members m
    where m.league_id = bracket_predictions.league_id and m.user_id = auth.uid()
  ));
create policy "users can insert own bracket predictions"
  on public.bracket_predictions for insert to authenticated with check (user_id = auth.uid());
create policy "users can update own bracket predictions"
  on public.bracket_predictions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users can delete own bracket predictions"
  on public.bracket_predictions for delete to authenticated using (user_id = auth.uid());

-- Code-login support. This lets The Pundits identify players by their permanent
-- 4-letter code instead of requiring a Supabase email session.
alter table public.profiles drop constraint if exists profiles_id_fkey;
alter table public.profiles add column if not exists access_code text unique;
create index if not exists profiles_access_code_idx on public.profiles (upper(access_code));

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
  found_profile public.profiles;
begin
  if clean_code = '' then
    raise exception 'Pundit code is required.';
  end if;

  select *
  into found_profile
  from public.profiles
  where upper(access_code) = clean_code
  limit 1;

  if found_profile.id is null then
    insert into public.profiles (id, email, squad_name, access_code)
    values (gen_random_uuid(), coalesce(nullif(p_email, ''), clean_code || '@thepundits.local'), coalesce(nullif(p_squad_name, ''), 'New Pundit'), clean_code)
    returning * into found_profile;
  else
    update public.profiles
    set email = coalesce(nullif(p_email, ''), found_profile.email),
        squad_name = coalesce(nullif(p_squad_name, ''), found_profile.squad_name)
    where id = found_profile.id
    returning * into found_profile;
  end if;

  return found_profile;
end;
$$;

grant execute on function public.upsert_code_profile(text, text, text) to anon, authenticated;

create or replace function public.get_profile_by_code(p_access_code text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  found_profile public.profiles;
begin
  select *
  into found_profile
  from public.profiles
  where upper(access_code) = upper(trim(p_access_code))
  limit 1;

  if found_profile.id is null then
    raise exception 'Code not found.';
  end if;

  return found_profile;
end;
$$;

grant execute on function public.get_profile_by_code(text) to anon, authenticated;

create or replace function public.create_league_with_code(
  p_access_code text,
  p_email text,
  p_squad_name text,
  p_name text
)
returns public.leagues
language plpgsql
security definer
set search_path = public
as $$
declare
  player public.profiles;
  created_league public.leagues;
  new_code text;
begin
  player := public.upsert_code_profile(p_access_code, p_email, p_squad_name);
  new_code := 'WC26-' || floor(1000 + random() * 9000)::int::text;

  while exists (select 1 from public.leagues where code = new_code) loop
    new_code := 'WC26-' || floor(1000 + random() * 9000)::int::text;
  end loop;

  insert into public.leagues (code, name, owner_id)
  values (new_code, coalesce(nullif(p_name, ''), new_code), player.id)
  returning * into created_league;

  insert into public.league_members (league_id, user_id)
  values (created_league.id, player.id)
  on conflict (league_id, user_id) do nothing;

  return created_league;
end;
$$;

grant execute on function public.create_league_with_code(text, text, text, text) to anon, authenticated;

create or replace function public.join_league_with_code(
  p_access_code text,
  p_email text,
  p_squad_name text,
  p_join_code text
)
returns public.leagues
language plpgsql
security definer
set search_path = public
as $$
declare
  player public.profiles;
  found_league public.leagues;
begin
  player := public.upsert_code_profile(p_access_code, p_email, p_squad_name);

  select *
  into found_league
  from public.leagues
  where upper(code) = upper(trim(p_join_code))
  limit 1;

  if found_league.id is null then
    raise exception 'League code not found.';
  end if;

  insert into public.league_members (league_id, user_id)
  values (found_league.id, player.id)
  on conflict (league_id, user_id) do nothing;

  return found_league;
end;
$$;

grant execute on function public.join_league_with_code(text, text, text, text) to anon, authenticated;

create or replace function public.get_leagues_for_code(p_access_code text)
returns table (id uuid, name text, code text, owner_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    return;
  end if;

  return query
  select distinct l.id, l.name, l.code, l.owner_id
  from public.leagues l
  left join public.league_members m on m.league_id = l.id
  where l.owner_id = player_id or m.user_id = player_id
  order by l.name;
end;
$$;

grant execute on function public.get_leagues_for_code(text) to anon, authenticated;

create or replace function public.get_predictions_with_code(
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
  group_rows jsonb;
  award_row jsonb;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    return jsonb_build_object('groups', '[]'::jsonb, 'award', null);
  end if;

  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb)
  into group_rows
  from public.group_predictions g
  where g.user_id = player_id and g.league_id = p_league_id;

  select to_jsonb(a)
  into award_row
  from public.award_predictions a
  where a.user_id = player_id and a.league_id = p_league_id
  limit 1;

  return jsonb_build_object('groups', group_rows, 'award', award_row);
end;
$$;

grant execute on function public.get_predictions_with_code(text, uuid) to anon, authenticated;

create or replace function public.save_predictions_with_code(
  p_access_code text,
  p_league_id uuid,
  p_group_picks jsonb,
  p_bonus jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid;
  item record;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    raise exception 'Pundit code not found.';
  end if;

  insert into public.league_members (league_id, user_id)
  values (p_league_id, player_id)
  on conflict (league_id, user_id) do nothing;

  for item in select key, value from jsonb_each(p_group_picks) loop
    insert into public.group_predictions (user_id, league_id, group_key, ordered_teams)
    values (player_id, p_league_id, item.key, item.value)
    on conflict (user_id, league_id, group_key)
    do update set ordered_teams = excluded.ordered_teams;
  end loop;

  insert into public.award_predictions (user_id, league_id, champion, top_scorer, top_assister)
  values (
    player_id,
    p_league_id,
    p_bonus->>'winner',
    p_bonus->>'scorer',
    p_bonus->>'assist'
  )
  on conflict (user_id, league_id)
  do update set
    champion = excluded.champion,
    top_scorer = excluded.top_scorer,
    top_assister = excluded.top_assister;

  return true;
end;
$$;

grant execute on function public.save_predictions_with_code(text, uuid, jsonb, jsonb) to anon, authenticated;

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
  public_picks boolean := now() >= '2026-06-11 22:00:00+03'::timestamptz;
  members_json jsonb;
  groups_json jsonb;
  awards_json jsonb;
begin
  select p.id into player_id
  from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code))
  limit 1;

  if player_id is null then
    raise exception 'Pundit code not found.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'profiles', jsonb_build_object('email', p.email, 'squad_name', p.squad_name)
  )), '[]'::jsonb)
  into members_json
  from public.league_members m
  join public.profiles p on p.id = m.user_id
  where m.league_id = p_league_id;

  select coalesce(jsonb_agg(to_jsonb(g)), '[]'::jsonb)
  into groups_json
  from public.group_predictions g
  where g.league_id = p_league_id
    and (public_picks or g.user_id = player_id);

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
  into awards_json
  from public.award_predictions a
  where a.league_id = p_league_id
    and (public_picks or a.user_id = player_id);

  return jsonb_build_object(
    'members', members_json,
    'groups', groups_json,
    'awards', awards_json,
    'picksArePublic', public_picks
  );
end;
$$;

grant execute on function public.get_league_entries_with_code(text, uuid) to anon, authenticated;
