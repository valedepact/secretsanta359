// Supabase Edge Function: send-event-reminders
// Invoked once a day by a pg_cron + pg_net job (see migration
// 20260714090000_group_edit_and_reminders.sql), never by the Flutter app.
// Finds every group whose event_date is "tomorrow" and hasn't been reminded
// for that specific event_date yet, then emails each participant.
//
// reminder_sent_for_date is compared against the *current* event_date, not
// just set to true/false - so if an organizer reschedules a group, the
// condition naturally becomes true again for the new date with no manual
// re-triggering needed.
//
// Unassigned participants (latecomers waiting to be paired) get a generic
// reminder with no mention of draw status, matching the same
// information-hiding rule the rest of the app follows.
//
// Only callable with the service-role key as the bearer token, since this
// is meant to run unattended from the cron job, not from any client.
//
// Required secrets (already set for the other email functions):
//   GMAIL_USER, GMAIL_APP_PASSWORD, APP_BASE_URL

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GMAIL_USER = Deno.env.get("GMAIL_USER")!;
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD")!;
const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://secretsanta359.app";

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (authHeader !== `Bearer ${SERVICE_ROLE_KEY}`) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: groups, error: groupsError } = await supabase
    .from("groups")
    .select("id, name, event_date, reminder_sent_for_date")
    .neq("status", "completed");
  if (groupsError) {
    return new Response(JSON.stringify({ error: groupsError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const now = new Date();
  const todayUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());

  const dueGroups = (groups ?? []).filter((g) => {
    const eventDate = new Date(g.event_date);
    const eventUtc = Date.UTC(eventDate.getUTCFullYear(), eventDate.getUTCMonth(), eventDate.getUTCDate());
    const diffDays = Math.round((eventUtc - todayUtc) / 86400000);
    return diffDays === 1 && g.reminder_sent_for_date !== g.event_date;
  });

  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
  });

  const results: { group_id: string; emailed: number }[] = [];

  for (const group of dueGroups) {
    const { data: participants } = await supabase
      .from("participants")
      .select("name, email, reveal_code, assigned_to_id")
      .eq("group_id", group.id)
      .not("email", "is", null);

    let emailed = 0;
    for (const participant of participants ?? []) {
      const hasAssignment = participant.assigned_to_id != null;
      const revealUrl = `${APP_BASE_URL}/join?reveal=${participant.reveal_code}`;
      try {
        await transporter.sendMail({
          from: GMAIL_USER,
          to: participant.email,
          subject: `Reminder: ${group.name} is tomorrow!`,
          html: hasAssignment
            ? `
              <p>Hi ${escapeHtml(participant.name)},</p>
              <p><strong>${escapeHtml(group.name)}</strong> is happening tomorrow!</p>
              <p>Need a reminder of who you're gifting? <a href="${revealUrl}">${revealUrl}</a></p>
            `
            : `
              <p>Hi ${escapeHtml(participant.name)},</p>
              <p><strong>${escapeHtml(group.name)}</strong> is happening tomorrow!</p>
              <p>Open the app to check your Secret Santa status: <a href="${APP_BASE_URL}">${APP_BASE_URL}</a></p>
            `,
        });
        emailed++;
      } catch (err) {
        console.error(`Failed to send reminder to ${participant.email}:`, err);
      }
    }

    await supabase
      .from("groups")
      .update({ reminder_sent_for_date: group.event_date })
      .eq("id", group.id);

    results.push({ group_id: group.id, emailed });
  }

  return new Response(JSON.stringify({ results }), {
    headers: { "Content-Type": "application/json" },
  });
});
