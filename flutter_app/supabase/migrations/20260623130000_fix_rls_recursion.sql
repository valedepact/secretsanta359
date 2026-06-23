-- The "participants can view groups they joined" policy on groups queries
-- participants, whose organizer policy queries groups right back - Postgres
-- detects this as infinite recursion (42P17) when evaluating either table.
-- A SECURITY DEFINER function breaks the cycle by bypassing RLS for the
-- inner existence check.

create or replace function is_participant_in_group(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from participants
    where participants.group_id = p_group_id
    and participants.user_id = p_user_id
  );
$$;

drop policy if exists "participants can view groups they joined" on groups;
create policy "participants can view groups they joined"
  on groups for select
  using (is_participant_in_group(groups.id, auth.uid()));
