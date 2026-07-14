-- Supports organizer-editable groups and a scheduled day-before-event
-- reminder email. No new RLS policy is needed for editing - the existing
-- "organizers manage own groups" ALL policy on groups already covers
-- updates to description/event_date by the owning organizer.

alter table groups add column if not exists reminder_sent_for_date timestamptz;

-- Enables a daily cron job to invoke an edge function via HTTP.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Calls send-event-reminders once a day. The function itself re-derives
-- which groups are "tomorrow" from the live event_date each run, so if an
-- organizer reschedules a group, the reminder automatically follows the new
-- date with no manual re-triggering needed.
select cron.schedule(
  'send-event-reminders-daily',
  '0 8 * * *',
  $$
  select net.http_post(
    url := 'https://nwtbovavfvskhwpdglat.supabase.co/functions/v1/send-event-reminders',
    headers := jsonb_build_object(
      'Authorization', 'Bearer REPLACE_WITH_SERVICE_ROLE_KEY',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
