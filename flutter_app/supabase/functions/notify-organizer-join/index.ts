// Supabase Edge Function: notify-organizer-join
// Triggered (fire-and-forget) right after a participant joins a group.
// Emails the organizer so they know someone joined without having to check
// the group details page manually.
//
// Required secrets (already set for send-reveal-emails, reused here):
//   GMAIL_USER, GMAIL_APP_PASSWORD, APP_BASE_URL
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GMAIL_USER = Deno.env.get("GMAIL_USER")!;
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD")!;
const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://secretsanta359.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const { group_id, participant_name } = await req.json();
  if (!group_id || !participant_name) {
    return new Response(
      JSON.stringify({ error: "group_id and participant_name are required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

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

  try {
    await transporter.sendMail({
      from: GMAIL_USER,
      to: organizer.user.email,
      subject: `${participant_name} joined "${group.name}"`,
      html: `
        <p>${participant_name} just joined your Secret Santa group <strong>${group.name}</strong>.</p>
        <p>View your group: <a href="${groupUrl}">${groupUrl}</a></p>
      `,
    });
    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Failed to notify organizer:", err);
    return new Response(JSON.stringify({ sent: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
