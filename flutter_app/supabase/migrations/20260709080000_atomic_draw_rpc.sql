-- Applies all draw assignments in a single transaction so a network
-- interruption can never leave a group in a half-drawn state.
-- The client computes the assignment map; this function writes it atomically.
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
