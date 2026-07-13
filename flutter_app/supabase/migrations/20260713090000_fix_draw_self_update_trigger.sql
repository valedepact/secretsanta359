-- perform_draw is SECURITY DEFINER but auth.uid() is still the calling
-- organizer's id, and triggers always fire regardless of SECURITY DEFINER.
-- When the organizer has also joined their own group as a participant
-- ("Join as a participant too"), the draw's bulk update touches the
-- organizer's own participant row, and restrict_participant_self_update_trigger
-- rejected the assigned_to_id/assigned_to_name change, rolling back the whole
-- draw with a 400. Exempt perform_draw's update via a transaction-local flag.

create or replace function restrict_participant_self_update()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('app.performing_draw', true), '') = 'true' then
    return new;
  end if;

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

create or replace function perform_draw(
  p_group_id uuid,
  p_assignments jsonb  -- array of {giver_id, giftee_id, giftee_name}
)
returns void
language plpgsql
security definer
as $$
begin
  -- Only the group organizer may trigger a draw.
  if not exists (
    select 1 from groups
    where id = p_group_id and organizer_id = auth.uid()
  ) then
    raise exception 'Not authorized to draw this group.';
  end if;

  -- Local to this transaction only; lets the self-update trigger allow the
  -- assigned_to_id/assigned_to_name writes below even if the organizer is
  -- also one of the participants being updated.
  perform set_config('app.performing_draw', 'true', true);

  -- Clear any prior (possibly partial) assignments before writing new ones.
  update participants
  set assigned_to_id = null, assigned_to_name = null
  where group_id = p_group_id;

  -- Write all assignments in one transaction.
  update participants as p
  set
    assigned_to_id   = (a->>'giftee_id')::uuid,
    assigned_to_name = a->>'giftee_name'
  from jsonb_array_elements(p_assignments) as a
  where p.id = (a->>'giver_id')::uuid;
end;
$$;

grant execute on function perform_draw(uuid, jsonb) to authenticated;
