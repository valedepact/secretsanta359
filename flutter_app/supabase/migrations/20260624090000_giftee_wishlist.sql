-- Lets a participant see the current wishlist of the person they're
-- assigned to gift, without granting broad read access to other
-- participants' rows. Reads the wishlist live (not a snapshot from draw
-- time) so edits made after the draw are reflected.
create or replace function get_my_giftee(p_group_id uuid)
returns table(name text, wishlist text)
language sql
security definer
stable
as $$
  select r.name, r.wishlist
  from participants g
  join participants r on r.id = g.assigned_to_id
  where g.group_id = p_group_id
    and g.user_id = auth.uid()
$$;

grant execute on function get_my_giftee(uuid) to authenticated;
