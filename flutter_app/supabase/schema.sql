-- Secret Santa Organizer schema
-- Run this in the Supabase SQL editor for the new project.

create extension if not exists "pgcrypto";

create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  budget numeric not null,
  currency text not null default 'UGX',
  event_date timestamptz not null,
  description text,
  status text not null default 'draft' check (status in ('draft', 'drawn', 'completed')),
  share_code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists participants (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  name text not null,
  gender text not null default 'other' check (gender in ('male', 'female', 'other')),
  email text,
  wishlist text,
  assigned_to_id uuid references participants(id),
  assigned_to_name text,
  reveal_code text not null unique,
  created_at timestamptz not null default now()
);

create index if not exists participants_group_id_idx on participants(group_id);

alter table groups enable row level security;
alter table participants enable row level security;

-- Organizers can fully manage their own groups.
create policy "organizers manage own groups"
  on groups for all
  using (auth.uid() = organizer_id)
  with check (auth.uid() = organizer_id);

-- Organizers can fully manage participants in their own groups.
create policy "organizers manage own participants"
  on participants for all
  using (
    exists (
      select 1 from groups
      where groups.id = participants.group_id
      and groups.organizer_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from groups
      where groups.id = participants.group_id
      and groups.organizer_id = auth.uid()
    )
  );

-- No public/anon policies on the raw tables: anonymous participants interact
-- exclusively through the SECURITY DEFINER RPC functions below, which expose
-- only the fields needed (never raw email/wishlist/assignment lists).

-- Look up a group's public info by its share code, for the join page.
create or replace function get_group_by_share_code(p_share_code text)
returns table (
  id uuid,
  name text,
  budget numeric,
  currency text,
  event_date timestamptz,
  description text,
  status text
)
language sql
security definer
set search_path = public
as $$
  select id, name, budget, currency, event_date, description, status
  from groups
  where share_code = p_share_code;
$$;

grant execute on function get_group_by_share_code(text) to anon, authenticated;

-- Join a group anonymously. Generates and returns the participant's reveal code.
create or replace function join_group(
  p_group_id uuid,
  p_name text,
  p_gender text,
  p_email text,
  p_wishlist text
)
returns table (id uuid, reveal_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reveal_code text;
  v_id uuid;
begin
  if not exists (select 1 from groups where groups.id = p_group_id and status = 'draft') then
    raise exception 'This group is not accepting new participants.';
  end if;

  v_reveal_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into participants (group_id, name, gender, email, wishlist, reveal_code)
  values (p_group_id, p_name, p_gender, p_email, p_wishlist, v_reveal_code)
  returning participants.id into v_id;

  return query select v_id, v_reveal_code;
end;
$$;

grant execute on function join_group(uuid, text, text, text, text) to anon, authenticated;

-- Private lookup: a participant's own name + who they are gifting.
create or replace function get_assignment_by_reveal_code(p_reveal_code text)
returns table (
  participant_name text,
  assigned_to_name text,
  group_name text
)
language sql
security definer
set search_path = public
as $$
  select p.name, p.assigned_to_name, g.name
  from participants p
  join groups g on g.id = p.group_id
  where p.reveal_code = p_reveal_code;
$$;

grant execute on function get_assignment_by_reveal_code(text) to anon, authenticated;

-- Full group reveal, only once the event date has passed.
create or replace function get_group_reveal(p_share_code text)
returns table (
  participant_name text,
  assigned_to_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_event_date timestamptz;
begin
  select id, event_date into v_group_id, v_event_date
  from groups where share_code = p_share_code;

  if v_group_id is null then
    raise exception 'Group not found.';
  end if;

  if now() < v_event_date then
    raise exception 'Reveal is not available until the event date.';
  end if;

  return query
    select p.name, p.assigned_to_name
    from participants p
    where p.group_id = v_group_id;
end;
$$;

grant execute on function get_group_reveal(text) to anon, authenticated;
