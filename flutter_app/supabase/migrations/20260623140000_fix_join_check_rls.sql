-- The participants insert policy's WITH CHECK queries groups to confirm the
-- group is still a draft. But a brand-new joiner isn't an organizer or an
-- existing participant yet, so groups' own RLS hides that row from them -
-- the EXISTS subquery always evaluates false and every first-time join is
-- rejected. A SECURITY DEFINER function bypasses RLS for this check, same
-- fix pattern as the groups-side recursion in the previous migration.

create or replace function is_group_accepting_participants(p_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from groups
    where groups.id = p_group_id
    and groups.status = 'draft'
  );
$$;

drop policy if exists "authenticated users can join draft groups" on participants;
create policy "authenticated users can join draft groups"
  on participants for insert
  with check (
    user_id = auth.uid()
    and is_group_accepting_participants(participants.group_id)
  );
