# Secret Santa Organizer (Flutter)

A web-first Flutter app for organizing Secret Santa gift exchanges. Organizers
sign in to create and manage groups; participants join via a shared link with
no account required, and privately reveal their assignment with a personal
reveal code.

## Features

- **Organizer accounts** via Supabase Auth (email/password)
- **Groups**: name, budget, currency (UGX), event date, description
- **No-account participant join** via `/join?code=<share_code>`
- **Gender-aware draw**: pairs male→female and female→male where possible,
  falls back gracefully on an uneven split, guarantees no self-assignment.
  Runs entirely client-side in the browser at draw time.
- **Private reveal**: each participant gets a unique 6-character reveal code,
  looked up at `/join?reveal=<code>`
- **Full group reveal**: unlocked for everyone only once the event date has
  passed (enforced server-side, not just hidden in the UI)
- **Email notifications**: after a draw, participants who gave an email get
  their reveal link sent via a Supabase Edge Function over Gmail SMTP
  (fire-and-forget — a failed send never blocks the draw)

## Architecture

```
Flutter (web + Android)
  ├── Auth: Supabase Auth (lib/services/auth_service.dart)
  ├── Data: Supabase Postgres (lib/services/group_service.dart,
  │         lib/services/participant_service.dart)
  ├── Draw logic: lib/utils/draw_algorithm.dart (runs in the browser)
  └── Email: lib/services/email_service.dart
            └── Supabase Edge Function (Deno) → Gmail SMTP → participant inboxes
```

### Why RPC functions instead of direct table access for participants

Anonymous participants (no Supabase Auth session) never read or write the
`groups` / `participants` tables directly. Row-Level Security locks both
tables to the owning organizer only. Anonymous flows — joining a group,
looking up your own assignment, viewing the full reveal — go through
`SECURITY DEFINER` Postgres functions (see `supabase/schema.sql`) that expose
only the specific fields each flow needs, and enforce rules like "the full
reveal is only readable after the event date" inside the function itself
rather than trusting the client.

## Project layout

```
lib/
  models/        Group, Participant, and public DTOs returned by RPCs
  services/       Supabase client, auth, group/participant CRUD, email trigger
  pages/         Landing, sign-in, dashboard, create group, group details, join/reveal
  utils/         draw algorithm, invite/reveal link builder, code generation
supabase/
  schema.sql                          tables, RLS policies, RPC functions
  functions/send-reveal-emails/       Deno edge function for reveal emails
  README.md                          backend setup steps
```

## Local setup

1. Install the Flutter SDK (stable channel) and enable web support:
   ```bash
   flutter config --enable-web
   ```
2. Copy the env template and fill in your Supabase project values:
   ```bash
   cp lib/utils/env.example.dart lib/utils/env.dart
   ```
   `lib/utils/env.dart` is gitignored — it holds your Supabase URL and anon
   key and must never be committed.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the database migration and deploy the edge function — see
   `supabase/README.md`.
5. Run the app:
   ```bash
   flutter run -d chrome   # web
   flutter run             # connected Android device/emulator
   ```

## Testing

```bash
flutter analyze
flutter test
```

## Building for release

```bash
flutter build web --release      # static site in build/web
flutter build apk --release      # Android APK in build/app/outputs
```

## Relationship to `chanel/`

This repository also contains `chanel/`, an earlier Flask + Supabase
implementation of the same concept (PIN-based admin access, no organizer
accounts, no email). The two are independent and do not share a database —
`flutter_app/` uses its own Supabase project. `chanel/` is left untouched.
