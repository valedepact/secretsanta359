-- Replaces automatic latecomer pairing with an organizer-triggered one.
-- Latecomers still join silently (is_group_accepting_participants already
-- allows 'drawn' groups from the previous migration) and wait unassigned,
-- but pairing them up is now a deliberate action the organizer takes -
-- not something that fires invisibly the moment a second person joins.

drop trigger if exists handle_latecomer_join_trigger on participants;
drop function if exists handle_latecomer_join();

-- Organizer-only: pairs up currently-unassigned participants in an
-- already-drawn group. The client computes the assignment (via
-- drawLatecomerAssignments, which allows a mutual pair when exactly 2 are
-- waiting, and the normal no-mutual-pairs algorithm for 3+) and this writes
-- it atomically. Only touches the rows passed in - never resets or
-- re-notifies anyone already assigned from the main draw.
create or replace function perform_latecomer_draw(
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

  update participants as p
  set
    assigned_to_id   = (a->>'giftee_id')::uuid,
    assigned_to_name = a->>'giftee_name'
  from jsonb_array_elements(p_assignments) as a
  where p.id = (a->>'giver_id')::uuid
    and p.group_id = p_group_id;
end;
$$;

grant execute on function perform_latecomer_draw(uuid, jsonb) to authenticated;
