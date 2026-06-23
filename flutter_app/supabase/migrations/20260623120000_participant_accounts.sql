-- Adds account-based participation: a participant can now be linked to a
-- Supabase Auth user. Anonymous join (via the join_group RPC) is still
-- supported for backwards compatibility, but the primary flow now requires
-- sign-in so a participant lands directly in their event after tapping an
-- invite link - no separate manual code entry, no separate reveal code to
-- remember.

alter table participants
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create index if not exists participants_user_id_idx on participants(user_id);

-- A reveal_code is still generated for every participant (used by the
-- legacy anonymous reveal flow and the reveal email), but authenticated
-- joins no longer need to pass one in explicitly.
alter table participants
  alter column reveal_code set default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

-- Authenticated participants can see their own participant rows directly.
create policy "participants can view own rows"
  on participants for select
  using (user_id = auth.uid());

-- Authenticated participants can join a group themselves (no RPC needed),
-- as long as the group is still accepting participants.
create policy "authenticated users can join draft groups"
  on participants for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from groups
      where groups.id = participants.group_id
      and groups.status = 'draft'
    )
  );

-- Participants can update their own row, but a trigger (below) restricts
-- this to the wishlist field only - never their own assignment, reveal
-- code, or identity fields.
create policy "participants can update own row"
  on participants for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function restrict_participant_self_update()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and old.user_id = auth.uid() then
    if new.name is distinct from old.name
      or new.gender is distinct from old.gender
      or new.email is distinct from old.email
      or new.group_id is distinct from old.group_id
      or new.assigned_to_id is distinct from old.assigned_to_id
      or new.assigned_to_name is distinct from old.assigned_to_name
      or new.reveal_code is distinct from old.reveal_code
      or new.user_id is distinct from old.user_id
    then
      raise exception 'Participants may only update their own wishlist.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists restrict_participant_self_update_trigger on participants;
create trigger restrict_participant_self_update_trigger
  before update on participants
  for each row
  execute function restrict_participant_self_update();

-- Authenticated participants can read the groups they've joined (the
-- organizer-only policy on groups already covers the organizer's own view).
create policy "participants can view groups they joined"
  on groups for select
  using (
    exists (
      select 1 from participants
      where participants.group_id = groups.id
      and participants.user_id = auth.uid()
    )
  );

-- Lets the join page resolve a share_code to a group_id once the visitor is
-- signed in, without exposing the full groups table.
create or replace function get_group_id_by_share_code(p_share_code text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select id from groups where share_code = p_share_code;
$$;

grant execute on function get_group_id_by_share_code(text) to anon, authenticated;
