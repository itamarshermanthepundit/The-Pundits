-- The Pundits email-only player login.
-- Run this entire file once in the Supabase SQL Editor.
-- Note: email-only login is convenient but does not verify email ownership.

create or replace function public.get_profile_by_email(p_email text)
returns public.profiles
language sql
security definer
set search_path = public
as $$
  select p
  from public.profiles p
  where lower(p.email) = lower(trim(p_email))
  order by p.created_at asc
  limit 1;
$$;

revoke all on function public.get_profile_by_email(text) from public;
grant execute on function public.get_profile_by_email(text) to anon, authenticated;
