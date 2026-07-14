// Supabase Edge Function: send-reveal-emails
// Triggered (fire-and-forget) right after a draw, and again after every
// participant join (a no-op unless a latecomer pairing just happened).
// Only emails participants with notified_at still null, so re-invoking this
// after a partial/incremental (latecomer) pairing never re-emails anyone
// who was already notified. A full redraw resets notified_at for everyone,
// so it correctly re-notifies the whole group in that case.
//
// Required secrets (set with `supabase secrets set`):
//   GMAIL_USER            - the Gmail address to send from
//   GMAIL_APP_PASSWORD    - a Gmail App Password (not the account password)
//   APP_BASE_URL          - public origin used to build reveal links, e.g. https://secretsanta359.app
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by the platform.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GMAIL_USER = Deno.env.get("GMAIL_USER")!;
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD")!;
const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://secretsanta359.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const { group_id } = await req.json();
  if (!group_id) {
    return new Response(JSON.stringify({ error: "group_id is required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const authClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: group, error: groupError } = await supabase
    .from("groups")
    .select("name, event_date, organizer_id")
    .eq("id", group_id)
    .single();
  if (groupError || !group) {
    return new Response(JSON.stringify({ error: "Group not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (group.organizer_id !== user.id) {
    return new Response(JSON.stringify({ error: "Not authorized for this group" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: participants, error: participantsError } = await supabase
    .from("participants")
    .select("id, name, email, reveal_code")
    .eq("group_id", group_id)
    .not("email", "is", null)
    .not("assigned_to_id", "is", null)
    .is("notified_at", null);
  if (participantsError) {
    return new Response(JSON.stringify({ error: participantsError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
  });

  const results: { email: string; sent: boolean }[] = [];

  for (const participant of participants ?? []) {
    const revealUrl = `${APP_BASE_URL}/join?reveal=${participant.reveal_code}`;
    try {
      await transporter.sendMail({
        from: GMAIL_USER,
        to: participant.email,
        subject: `Names have been drawn for ${group.name}!`,
        html: `
          <p>Hi ${escapeHtml(participant.name)},</p>
          <p>Names have been drawn for <strong>${escapeHtml(group.name)}</strong>.</p>
          <p>Your personal reveal code is <strong>${participant.reveal_code}</strong>.</p>
          <p>See who you're gifting here: <a href="${revealUrl}">${revealUrl}</a></p>
          <p>The full group reveal unlocks on the event date.</p>
        `,
      });
      await supabase
        .from("participants")
        .update({ notified_at: new Date().toISOString() })
        .eq("id", participant.id);
      results.push({ email: participant.email, sent: true });
    } catch (err) {
      console.error(`Failed to send to ${participant.email}:`, err);
      results.push({ email: participant.email, sent: false });
    }
  }

  return new Response(JSON.stringify({ results }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
