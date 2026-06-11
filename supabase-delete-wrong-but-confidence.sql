-- Confirmed account removal: "wrong but confidence"
-- Run this entire file once in the Supabase SQL Editor.
-- It backs up the account, transfers owned leagues to the admin, then removes
-- only this account's profile, memberships, and predictions.

do $$
declare
  target_profile public.profiles;
  admin_profile public.profiles;
  matching_accounts integer;
begin
  select count(*) into matching_accounts
  from public.profiles
  where lower(trim(squad_name)) = 'wrong but confidence';

  if matching_accounts <> 1 then
    raise exception 'Safety stop: expected exactly 1 matching account, found %.', matching_accounts;
  end if;

  select * into target_profile
  from public.profiles
  where lower(trim(squad_name)) = 'wrong but confidence'
  limit 1;

  select * into admin_profile
  from public.profiles
  where lower(email) = 'itamarsherman@gmail.com'
  order by created_at asc
  limit 1;

  if admin_profile.id is null then
    raise exception 'Safety stop: admin profile was not found.';
  end if;

  create table if not exists public.pundits_deleted_account_backups (
    id uuid primary key default gen_random_uuid(),
    deleted_at timestamptz not null default now(),
    profile jsonb not null,
    owned_leagues jsonb not null,
    memberships jsonb not null,
    group_predictions jsonb not null,
    award_predictions jsonb not null,
    bracket_predictions jsonb not null
  );

  alter table public.pundits_deleted_account_backups enable row level security;
  revoke all on public.pundits_deleted_account_backups from public, anon, authenticated;

  insert into public.pundits_deleted_account_backups (
    profile,
    owned_leagues,
    memberships,
    group_predictions,
    award_predictions,
    bracket_predictions
  )
  values (
    to_jsonb(target_profile),
    coalesce((select jsonb_agg(to_jsonb(l)) from public.leagues l where l.owner_id = target_profile.id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(m)) from public.league_members m where m.user_id = target_profile.id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(g)) from public.group_predictions g where g.user_id = target_profile.id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(a)) from public.award_predictions a where a.user_id = target_profile.id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(b)) from public.bracket_predictions b where b.user_id = target_profile.id), '[]'::jsonb)
  );

  update public.leagues
  set owner_id = admin_profile.id
  where owner_id = target_profile.id;

  update public.official_results
  set updated_by = null
  where updated_by = target_profile.id;

  delete from public.profiles
  where id = target_profile.id;

  raise notice 'Account "wrong but confidence" was removed safely.';
end;
$$;
