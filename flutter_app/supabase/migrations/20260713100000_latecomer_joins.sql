-- Allows people to join a group after the draw has already happened.
-- They wait unassigned until at least one other latecomer has also joined,
-- then get auto-paired with each other (existing participants' assignments
-- are never touched or re-notified). A single latecomer with no one to pair
-- with stays unassigned indefinitely - accepted as fine for now.

-- 1. Let joins through once a group is 'drawn' (still blocked once 'completed').
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
    and groups.status in ('draft', 'drawn')
  );
$$;

-- 2. Tracks whether a participant has already been emailed their reveal
-- link, so re-invoking send-reveal-emails after a latecomer pairing only
-- emails the newly-paired latecomers, not the whole group again.
alter table participants add column if not exists notified_at timestamptz;

-- 3. A full redraw should re-notify everyone with their new assignment.
create or replace function perform_draw(
  p_group_id uuid,
  p_assignments jsonb  -- array of {giver_id, giftee_id, giftee_name}
)
returns void
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from groups
    where id = p_group_id and organizer_id = auth.uid()
  ) then
    raise exception 'Not authorized to draw this group.';
  end if;

  perform set_config('app.performing_draw', 'true', true);

  update participants
  set assigned_to_id = null, assigned_to_name = null, notified_at = null
  where group_id = p_group_id;

  update participants as p
  set
    assigned_to_id   = (a->>'giftee_id')::uuid,
    assigned_to_name = a->>'giftee_name'
  from jsonb_array_elements(p_assignments) as a
  where p.id = (a->>'giver_id')::uuid;
end;
$$;

grant execute on function perform_draw(uuid, jsonb) to authenticated;

-- 4. Whenever someone joins a group that's already been drawn, check if
-- there are now 2+ unassigned participants and, if so, pair them up with a
-- simple cyclic derangement (i -> i+1, wrapping). For exactly 2 people this
-- is a mutual pair, same as the smallest possible normal draw.
create or replace function handle_latecomer_join()
returns trigger
language plpgsql
security definer
as $$
declare
  v_status text;
  v_ids uuid[];
  v_names text[];
  n int;
begin
  select status into v_status from groups where id = new.group_id;
  if v_status is distinct from 'drawn' then
    return new;
  end if;

  select array_agg(id order by created_at), array_agg(name order by created_at)
    into v_ids, v_names
    from participants
    where group_id = new.group_id and assigned_to_id is null;

  n := coalesce(array_length(v_ids, 1), 0);
  if n < 2 then
    return new;
  end if;

  perform set_config('app.performing_draw', 'true', true);

  for i in 1..n loop
    update participants
    set assigned_to_id = v_ids[(i % n) + 1],
        assigned_to_name = v_names[(i % n) + 1]
    where id = v_ids[i];
  end loop;

  return new;
end;
$$;

drop trigger if exists handle_latecomer_join_trigger on participants;
create trigger handle_latecomer_join_trigger
  after insert on participants
  for each row
  execute function handle_latecomer_join();
