-- The Pundits safe group-stage lock and friend-picks reveal.
-- Run this entire file once BEFORE pressing Lock picks.

create table if not exists public.pundits_prediction_snapshots (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  group_predictions jsonb not null,
  award_predictions jsonb not null
);

alter table public.pundits_prediction_snapshots enable row level security;
revoke all on public.pundits_prediction_snapshots from public, anon, authenticated;

create or replace function public.admin_password_set_tournament_setting(
  p_token uuid,
  p_key text,
  p_value jsonb
)
returns public.official_results
language plpgsql
security definer
set search_path = public
as $$
declare saved public.official_results;
begin
  if not public.valid_pundits_admin_token(p_token) then raise exception 'Admin session expired.'; end if;

  if p_key = 'group_picks_locked' and p_value = 'true'::jsonb then
    insert into public.pundits_prediction_snapshots (group_predictions, award_predictions)
    values (
      coalesce((select jsonb_agg(to_jsonb(g)) from public.group_predictions g), '[]'::jsonb),
      coalesce((select jsonb_agg(to_jsonb(a)) from public.award_predictions a), '[]'::jsonb)
    );
  end if;

  insert into public.official_results (result_type, result_key, value, updated_at)
  values ('setting', p_key, p_value, now())
  on conflict (result_type, result_key)
  do update set value = excluded.value, updated_at = now()
  returning * into saved;
  return saved;
end;
$$;

grant execute on function public.admin_password_set_tournament_setting(uuid, text, jsonb) to anon, authenticated;

create or replace function public.protect_locked_group_picks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare locked boolean := false;
begin
  select coalesce((value #>> '{}')::boolean, false) into locked
  from public.official_results
  where result_type = 'setting' and result_key = 'group_picks_locked'
  limit 1;

  if locked then raise exception 'Group-stage predictions are locked.'; end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists protect_locked_group_predictions on public.group_predictions;
create trigger protect_locked_group_predictions
before insert or update or delete on public.group_predictions
for each row execute function public.protect_locked_group_picks();

drop trigger if exists protect_locked_award_predictions on public.award_predictions;
create trigger protect_locked_award_predictions
before insert or update or delete on public.award_predictions
for each row execute function public.protect_locked_group_picks();

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
  select p.id into player_id from public.profiles p
  where upper(p.access_code) = upper(trim(p_access_code)) limit 1;
  if player_id is null then raise exception 'Player account not found.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'profiles', jsonb_build_object('email', p.email, 'squad_name', p.squad_name)
  ) order by p.squad_name), '[]'::jsonb)
  into members_json
  from public.league_members m join public.profiles p on p.id = m.user_id
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

grant execute on function public.get_league_entries_with_code(text, uuid) to anon, authenticated;

create or replace function public.get_league_entries_for_user(p_league_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  player_id uuid := auth.uid();
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
  if player_id is null then raise exception 'Sign in first.'; end if;
  if not exists (
    select 1 from public.league_members where league_id = p_league_id and user_id = player_id
  ) then raise exception 'Join this league first.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'profiles', jsonb_build_object('email', p.email, 'squad_name', p.squad_name)
  ) order by p.squad_name), '[]'::jsonb)
  into members_json
  from public.league_members m join public.profiles p on p.id = m.user_id
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
