-- The Pundits database schema for Supabase.
-- Run this in the Supabase SQL editor after creating a project.

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  squad_name text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.leagues (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.league_members (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (league_id, user_id)
);

create table public.group_predictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  group_key text not null,
  ordered_teams jsonb not null,
  locked_at timestamptz,
  unique (user_id, league_id, group_key)
);

create table public.award_predictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  champion text,
  top_scorer text,
  top_assister text,
  locked_at timestamptz,
  unique (user_id, league_id)
);

create table public.bracket_predictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  match_key text not null,
  picked_winner text,
  predicted_home_score integer,
  predicted_away_score integer,
  locked_at timestamptz,
  unique (user_id, league_id, match_key)
);

create table public.official_results (
  id uuid primary key default gen_random_uuid(),
  result_type text not null,
  result_key text not null,
  value jsonb not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  unique (result_type, result_key)
);

alter table public.profiles enable row level security;
alter table public.leagues enable row level security;
alter table public.league_members enable row level security;
alter table public.group_predictions enable row level security;
alter table public.award_predictions enable row level security;
alter table public.bracket_predictions enable row level security;
alter table public.official_results enable row level security;

create policy "profiles are visible to signed in users"
  on public.profiles for select to authenticated using (true);

create policy "users can insert own profile"
  on public.profiles for insert to authenticated with check (auth.uid() = id);

create policy "users can update own profile"
  on public.profiles for update to authenticated using (auth.uid() = id);

create policy "authenticated users can find leagues"
  on public.leagues for select to authenticated using (true);

create policy "users can create leagues"
  on public.leagues for insert to authenticated with check (owner_id = auth.uid());

create policy "memberships visible to league members"
  on public.league_members for select to authenticated
  using (user_id = auth.uid() or exists (
    select 1 from public.league_members mine
    where mine.league_id = league_members.league_id and mine.user_id = auth.uid()
  ));

create policy "users can join leagues"
  on public.league_members for insert to authenticated with check (user_id = auth.uid());

create policy "users manage own group predictions"
  on public.group_predictions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "users manage own award predictions"
  on public.award_predictions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "users manage own bracket predictions"
  on public.bracket_predictions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "results visible to everyone signed in"
  on public.official_results for select to authenticated using (true);

create policy "admins manage results"
  on public.official_results for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
