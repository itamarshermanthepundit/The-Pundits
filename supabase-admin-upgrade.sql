-- The Pundits admin controls.
-- Run this once in the Supabase SQL Editor.

create or replace function public.is_pundits_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt()->>'email', '')) = 'itamarsherman@gmail.com';
$$;

grant execute on function public.is_pundits_admin() to anon, authenticated;

update public.profiles
set is_admin = true
where lower(email) = 'itamarsherman@gmail.com';

drop policy if exists "results visible to everyone signed in" on public.official_results;
drop policy if exists "results visible to everyone" on public.official_results;
create policy "results visible to everyone"
  on public.official_results for select to anon, authenticated using (true);

drop policy if exists "admins manage results" on public.official_results;
create policy "admins manage results"
  on public.official_results for all to authenticated
  using (public.is_pundits_admin())
  with check (public.is_pundits_admin());

create or replace function public.admin_set_tournament_setting(
  p_key text,
  p_value jsonb
)
returns public.official_results
language plpgsql
security definer
set search_path = public
as $$
declare
  saved public.official_results;
begin
  if not public.is_pundits_admin() then
    raise exception 'Admin access required.';
  end if;

  insert into public.official_results (result_type, result_key, value, updated_by, updated_at)
  values ('setting', p_key, p_value, auth.uid(), now())
  on conflict (result_type, result_key)
  do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now()
  returning * into saved;

  return saved;
end;
$$;

grant execute on function public.admin_set_tournament_setting(text, jsonb) to authenticated;

create or replace function public.protect_locked_group_picks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  locked boolean := false;
begin
  select coalesce((value #>> '{}')::boolean, false)
  into locked
  from public.official_results
  where result_type = 'setting' and result_key = 'group_picks_locked'
  limit 1;

  if locked then
    raise exception 'Group-stage predictions are locked.';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
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
