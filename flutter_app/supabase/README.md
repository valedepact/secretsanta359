# Backend setup

## 1. Database

Run `schema.sql` in the Supabase SQL editor for the project.

## 2. Edge Function (reveal emails)

Requires the [Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
supabase login
supabase link --project-ref <your-project-ref>

supabase secrets set GMAIL_USER=youraddress@gmail.com
supabase secrets set GMAIL_APP_PASSWORD=your16charapppassword
supabase secrets set APP_BASE_URL=https://your-deployed-app-url

supabase functions deploy send-reveal-emails
```

The function is invoked automatically by the Flutter app right after a draw
(`EmailService.sendRevealEmails`) and is fire-and-forget - email failures
never block the draw itself.
