// Supabase Edge Function: notify-organizer-join
// Triggered (fire-and-forget) right after a participant joins a group.
// Emails the organizer so they know someone joined without having to check
// the group details page manually, and welcome-emails the participant who
// just joined.
//
// Required secrets (already set for send-reveal-emails, reused here):
//   GMAIL_USER, GMAIL_APP_PASSWORD, APP_BASE_URL
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

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

  // The joining participant's own name is looked up server-side from their
  // own row (matched by group_id + their authenticated user_id) rather than
  // trusted from the request body - closes both the "anyone can email the
  // organizer for any group" hole and the HTML-injection vector in one move.
  const { data: participant, error: participantError } = await supabase
    .from("participants")
    .select("name, email")
    .eq("group_id", group_id)
    .eq("user_id", user.id)
    .single();
  if (participantError || !participant) {
    return new Response(JSON.stringify({ error: "Not a participant of this group" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const participant_name = participant.name;

  const { data: group, error: groupError } = await supabase
    .from("groups")
    .select("name, organizer_id, share_code")
    .eq("id", group_id)
    .single();
  if (groupError || !group) {
    return new Response(JSON.stringify({ error: "Group not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: organizer, error: organizerError } =
    await supabase.auth.admin.getUserById(group.organizer_id);
  if (organizerError || !organizer.user?.email) {
    return new Response(JSON.stringify({ error: "Organizer not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
  });

  const groupUrl = `${APP_BASE_URL}/group/${group_id}`;

  let organizerSent = false;
  try {
    await transporter.sendMail({
      from: GMAIL_USER,
      to: organizer.user.email,
      subject: `${participant_name} joined "${group.name}"`,
      html: `
        <p>${escapeHtml(participant_name)} just joined your Secret Santa group <strong>${escapeHtml(group.name)}</strong>.</p>
        <p>View your group: <a href="${groupUrl}">${groupUrl}</a></p>
      `,
    });
    organizerSent = true;
  } catch (err) {
    console.error("Failed to notify organizer:", err);
  }

  // Welcome-email the participant too, if they have one on file. Independent
  // of the organizer email above - one failing shouldn't block the other.
  let participantSent = false;
  if (participant.email) {
    try {
      await transporter.sendMail({
        from: GMAIL_USER,
        to: participant.email,
        subject: `You're in for "${group.name}"!`,
        html: `
          <p>Hi ${escapeHtml(participant_name)},</p>
          <p>You've joined <strong>${escapeHtml(group.name)}</strong>. Once the organizer draws names,
          we'll email you a link to see who you're gifting.</p>
          <p>Sign in anytime at <a href="${APP_BASE_URL}">${APP_BASE_URL}</a> to check your groups.</p>
        `,
      });
      participantSent = true;
    } catch (err) {
      console.error("Failed to welcome-email participant:", err);
    }
  }

  return new Response(JSON.stringify({ organizerSent, participantSent }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
