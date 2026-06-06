-- The Pundits password-only admin access.
-- Run this entire file once in the Supabase SQL Editor.
-- The public app never receives or stores the admin password.

create extension if not exists pgcrypto;

create table if not exists public.pundits_admin_sessions (
  token uuid primary key default gen_random_uuid(),
  expires_at timestamptz not null default now() + interval '12 hours',
  created_at timestamptz not null default now()
);

alter table public.pundits_admin_sessions enable row level security;
revoke all on public.pundits_admin_sessions from public, anon, authenticated;

create or replace function public.valid_pundits_admin_token(p_token uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pundits_admin_sessions
    where token = p_token and expires_at > now()
  );
$$;

create or replace function public.admin_password_login(p_password text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  new_token uuid;
begin
  if encode(digest(coalesce(p_password, ''), 'sha256'), 'hex')
      <> '2959b8a8ff85f908d1429fac3cbadfec2b9356e827c7ad13ed8ed01b24a07a12' then
    perform pg_sleep(1);
    raise exception 'Password is incorrect.';
  end if;

  delete from public.pundits_admin_sessions where expires_at <= now();
  insert into public.pundits_admin_sessions default values returning token into new_token;
  return new_token;
end;
$$;

create or replace function public.admin_password_get_stats(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.valid_pundits_admin_token(p_token) then raise exception 'Admin session expired.'; end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'leagues', (select count(*) from public.leagues),
    'memberships', (select count(*) from public.league_members)
  );
end;
$$;

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
  insert into public.official_results (result_type, result_key, value, updated_at)
  values ('setting', p_key, p_value, now())
  on conflict (result_type, result_key)
  do update set value = excluded.value, updated_at = now()
  returning * into saved;
  return saved;
end;
$$;

create or replace function public.admin_password_save_result(
  p_token uuid,
  p_result_type text,
  p_result_key text,
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
  insert into public.official_results (result_type, result_key, value, updated_at)
  values (p_result_type, p_result_key, p_value, now())
  on conflict (result_type, result_key)
  do update set value = excluded.value, updated_at = now()
  returning * into saved;
  return saved;
end;
$$;

revoke all on function public.valid_pundits_admin_token(uuid) from public;
revoke all on function public.admin_password_login(text) from public;
revoke all on function public.admin_password_get_stats(uuid) from public;
revoke all on function public.admin_password_set_tournament_setting(uuid, text, jsonb) from public;
revoke all on function public.admin_password_save_result(uuid, text, text, jsonb) from public;

grant execute on function public.admin_password_login(text) to anon, authenticated;
grant execute on function public.admin_password_get_stats(uuid) to anon, authenticated;
grant execute on function public.admin_password_set_tournament_setting(uuid, text, jsonb) to anon, authenticated;
grant execute on function public.admin_password_save_result(uuid, text, text, jsonb) to anon, authenticated;
