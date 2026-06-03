-- The Pundits dashboard upgrade.
-- Run this once in Supabase SQL Editor after the original schema.

drop policy if exists "leagues visible to members" on public.leagues;
drop policy if exists "authenticated users can find leagues" on public.leagues;
create policy "authenticated users can find leagues"
  on public.leagues for select to authenticated using (true);

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
