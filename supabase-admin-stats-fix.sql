-- The Pundits admin statistics fix.
-- Run this entire file once in the Supabase SQL Editor.

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
