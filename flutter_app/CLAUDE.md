# Secret Santa Organizer — Project Brief for Claude Code

Flutter web + Android app. Deployed at https://secretsanta359.netlify.app.
GitHub: valedepact/secretsanta359, branch `morningstar1`.
Legacy Python/Flask app is in `../chanel/` — **do not touch it**.

## Architecture

| Layer | Tool |
|---|---|
| Frontend | Flutter (web-first, also Android APK) |
| Backend / DB | Supabase (Postgres + Auth + Edge Functions) |
| Web hosting | Netlify |
| Email | Gmail SMTP via nodemailer in Supabase Edge Functions |
| Routing | go_router with `usePathUrlStrategy()` |

## Supabase project

- URL: `https://nwtbovavfvskhwpdglat.supabase.co`
- Anon key: in `lib/utils/env.dart`
- Project ref: `nwtbovavfvskhwpdglat`
- Link locally: `supabase link --project-ref nwtbovavfvskhwpdglat` (inside this directory)
- Deploy migrations: `supabase db push`
- Deploy edge functions: `supabase functions deploy <name>`

Supabase secrets already set (via `supabase secrets set`): `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `APP_BASE_URL`.
`GMAIL_USER` is a dedicated sending account (`secretsanta14726@gmail.com`), not a personal address — keep it that way if it's ever rotated.

## Netlify deployment

Site: secretsanta359.netlify.app
```bash
flutter build web --release
netlify deploy --prod --dir=build/web --auth <token>
```
`web/_redirects` contains `/* /index.html 200` for SPA routing.

## Critical known constraint — DO NOT change this

**`supabase_flutter` is pinned to exactly `2.14.2` in `pubspec.yaml`.**
Version 2.15.0 introduced a web regression (`Null check operator used on a null value` during `Supabase.initialize()`) that produces a blank page on all web browsers. This was confirmed by bisecting versions. Do not run `flutter pub upgrade` on this package until the regression is confirmed fixed upstream.

## Auth model

- Both organizers and participants have Supabase Auth accounts.
- Email confirmation is disabled in the Supabase Auth settings (deliberate).
- Invite flow: tapping a share link goes to `/join?code=<shareCode>`. The `_JoinForm` widget handles sign-in/register inline (no separate page navigation, so the code stays in the URL). After auth, the user lands directly on their event page — no manual code entry.
- Manual code entry fallback exists at `/join` (no query params) for cases without a link.

## RLS — important history

Three migrations fix real production bugs found during development:

1. **`20260623130000_fix_rls_recursion.sql`**: `groups`' participant-visibility policy queried `participants`, whose organizer policy queried `groups` back → infinite recursion (Postgres error 42P17). Fixed with `is_participant_in_group()` SECURITY DEFINER function.

2. **`20260623140000_fix_join_check_rls.sql`**: The participants INSERT policy's `WITH CHECK` queried `groups` to verify `status='draft'`, but a brand-new joiner can't see that row yet under `groups`' own RLS → 403 on every first join. Fixed with `is_group_accepting_participants()` SECURITY DEFINER function.

3. **`20260624090000_giftee_wishlist.sql`**: Adds `get_my_giftee(p_group_id)` SECURITY DEFINER RPC so a participant can read their giftee's current wishlist without a broad SELECT grant on other participants' rows.

4. **`20260709080000_atomic_draw_rpc.sql`**: The original draw made N separate REST calls (one per participant). If interrupted, the group was left half-drawn with no way to recover cleanly. Fixed with `perform_draw(p_group_id, p_assignments)` SECURITY DEFINER RPC that writes all assignments in a single transaction.

5. **`20260713090000_fix_draw_self_update_trigger.sql`**: When the organizer is also a participant in their own group, `perform_draw`'s bulk update was silently blocked (HTTP 400) by `restrict_participant_self_update_trigger` — SECURITY DEFINER changes the RLS/privilege context but **not** `auth.uid()`, and triggers still fire regardless of SECURITY DEFINER. Fixed with a transaction-local session flag: `perform_draw` calls `set_config('app.performing_draw', 'true', true)` before the update, and the trigger self-exempts when that flag is set (`current_setting('app.performing_draw', true) = 'true'`).

6. **`20260713100000_latecomer_joins.sql`**: Adds `notified_at timestamptz` to `participants` (gates reveal emails so redraws/latecomer pairings don't re-email everyone) and updates `is_group_accepting_participants()` to also allow joins while `status = 'drawn'`. Originally also added a trigger to auto-pair latecomers on INSERT — **that trigger was removed in the next migration** in favor of an organizer-triggered flow (see below).

7. **`20260713110000_organizer_latecomer_draw.sql`**: Drops the auto-pairing trigger from migration 6 and adds `perform_latecomer_draw(p_group_id, p_assignments)` SECURITY DEFINER RPC — pairing latecomers is a deliberate organizer action, never automatic.

8. **`20260714090000_group_edit_and_reminders.sql`**: Adds `reminder_sent_for_date timestamptz` to `groups`, enables `pg_cron` + `pg_net`, and schedules a daily cron job (`send-event-reminders-daily`, `0 8 * * *`) that HTTP-posts to the `send-event-reminders` edge function. No new RLS policy needed for organizer group edits — the existing "organizers manage own groups" `ALL` policy already covers it. **The committed migration file keeps a `REPLACE_WITH_SERVICE_ROLE_KEY` placeholder in the cron job body — the real service-role key was substituted only into the one-off apply payload sent to the Management API, never committed.** If this migration is ever re-applied from scratch, that placeholder must be swapped for the real key at apply time, not in the file.

## Draw algorithm

`lib/utils/draw_algorithm.dart`:
- Prefers cross-gender pairs (male→female, female→male).
- Falls back to random derangement if gender split is uneven.
- **2-cycles (mutual pairs, e.g. A→B and B→A) are explicitly rejected** — the algorithm retries up to 200 times to find a non-reciprocal arrangement. This was a real bug found in a production draw.
- Known limitation (not a bug to fix, just a property of the rejection rule above): `drawAssignments` can **never** succeed for exactly 2 total participants, since the only possible outcome for 2 people is a mutual pair, which is always rejected. This is fine for the main draw (2-person groups are an edge case) but directly motivated the separate `drawLatecomerAssignments` function below.

## Latecomers joining after the draw

A participant can still join a group whose status is `drawn` (not just `draft`) — enforced by `is_group_accepting_participants()`. They wait unassigned until the organizer manually pairs them up; **there is no automatic pairing**, by deliberate design.

- `GroupDetailsPage` shows a "Pair up N latecomers" button once 2+ unassigned participants exist in a drawn group (or a passive "waiting" message if there's exactly 1 — a lone latecomer has no valid pairing and must wait for at least one more joiner).
- The button calls `ParticipantService.drawLatecomersAndAssign`, which computes the assignment client-side via `drawLatecomerAssignments` (allows a mutual pair only when exactly 2 are pending, since that's the only mathematically possible outcome for 2 people; reuses the normal no-mutual-pairs algorithm for 3+) and writes it via the `perform_latecomer_draw` RPC. Only the newly-paired rows are touched — everyone from the original draw keeps their assignment untouched and unaffected.
- Reveal emails are then re-triggered (`EmailService.sendRevealEmails`), but the `notified_at` gating in the edge function ensures only the newly-paired latecomers actually receive an email — nobody already notified gets a duplicate.
- **Participant-facing UI must never reveal that a group has already been drawn.** A latecomer sees the exact same generic "Names haven't been drawn yet - check back later" copy a pre-draw participant sees. The organizer is the only one who sees draw status and pairing controls — this was an explicit product decision, not an oversight.

## Email edge functions

All three functions use `npm:nodemailer@6.9.16` with Gmail SMTP (port 465, SSL). **Do not switch to `denomailer` from deno.land/x** — it causes `BOOT_ERROR` in Supabase's Edge Runtime (confirmed by bisecting imports).

- `supabase/functions/send-reveal-emails/` — triggered after a draw (and after organizer-triggered latecomer pairings), emails participants their reveal code and access link. Only emails rows where `assigned_to_id is not null and notified_at is null`, and sets `notified_at` after each successful send — this makes it safe to call repeatedly (e.g. after pairing latecomers) without re-emailing everyone. A full redraw resets `notified_at` to null for the whole group so everyone gets re-notified. Organizer-only: checks `group.organizer_id === caller` before sending.
- `supabase/functions/notify-organizer-join/` — triggered when someone joins. Emails the organizer that a new participant joined, **and** welcome-emails the joining participant with a note that a reveal link will follow once the organizer draws. Participant-only: the caller must be a participant row on the group (matched by `user_id`), and `participant_name` is looked up server-side from that row rather than trusted from the request body.
- `supabase/functions/send-event-reminders/` — **not called by the Flutter app at all.** Invoked once a day by the `send-event-reminders-daily` pg_cron job (see migration 8 above). Finds every non-completed group whose `event_date` is exactly tomorrow (UTC) and whose `reminder_sent_for_date` doesn't already match the current `event_date`, then emails every participant with an email on file. Comparing against the *live* `event_date` (not a boolean flag) makes the whole system self-correcting: if an organizer reschedules a group after a reminder already went out, the condition becomes true again for the new date automatically, with no manual re-triggering. Only callable with the service-role key as bearer token (rejects anything else with 403) — this is intentionally not reachable by any client. Follows the same information-hiding rule as the rest of the app: unassigned/latecomer participants get a generic "check your status" reminder with no mention of whether a draw happened.
- **Both `send-reveal-emails` and `notify-organizer-join` require a real caller `Authorization` header**, resolved via a second Supabase client created per-request from `SUPABASE_ANON_KEY` + the caller's header, then `.auth.getUser()`. `verify_jwt: true` alone is *not* sufficient authorization — the public anon key is itself a valid JWT, so any signed-in caller could invoke these functions for *any* group's data unless the function itself checks caller identity against the resource. This was a real finding from an authorized pentest of the production stack (see "Security" below) and is now fixed in both functions.
- **All user-controlled strings interpolated into email HTML (`participant.name`, `group.name`) are passed through a shared `escapeHtml()` helper** in every function that builds HTML — trusted-sender email is still a phishing-enablement vector if a participant can put `<img onerror=...>` in their display name.
- **All functions must handle CORS explicitly** (except `send-event-reminders`, which is cron/service-role-only and never called from a browser): `Deno.serve` needs to short-circuit `OPTIONS` preflight requests and attach `Access-Control-Allow-Origin` / `Access-Control-Allow-Headers` to every response (including error responses), or the browser blocks the call client-side (`net::ERR_FAILED`) before it reaches server code.

Also use `https://esm.sh/@supabase/supabase-js@2` (not `jsr:@supabase/supabase-js@2`) — the jsr: import also fails to boot.

## Security

An authorized pentest of the live production stack (real JWTs, throwaway `@example.com` test accounts, full cleanup after) found 4 issues:

1. **FIXED** — broken access control (IDOR) on `send-reveal-emails` and `notify-organizer-join`: any signed-in user could trigger either function for any group. Fixed by resolving real caller identity server-side (see above).
2. **FIXED** — HTML injection into trusted-sender emails via unescaped `participant.name`/`group.name`. Fixed via `escapeHtml()`.
3. **DEFERRED, needs a decision before fixing** — `get_assignment_by_reveal_code(text)` is granted to `anon`, reveal codes are only 6 hex chars (~16.7M keyspace) generated in `20260623120000_participant_accounts.sql:17`, not scoped to any group, with no rate limiting — brute-forceable. Fixing needs a call on whether to regenerate all existing codes (breaks already-sent links) or only harden newly-generated ones.
4. **NOT FIXED, not yet requested** — `perform_draw`/`perform_latecomer_draw` trust the client-submitted assignment mapping with no self-assignment or duplicate-giftee check server-side. Low real-world exploitability since only a group's own organizer can call it.

## Android

- Application ID: `ug.secretsanta359.app` (in `android/app/build.gradle.kts` and `android/app/src/main/kotlin/ug/secretsanta359/app/MainActivity.kt`)
- **Do not change this back to `com.example.*`** — it causes silent install failures (signing certificate conflict) if any other Flutter template app is installed on the device.
- `.apk` files cannot be installed on iOS — this is a platform limitation, not a bug.

## PWA install

`web/index.html` captures the browser's `beforeinstallprompt` event and exposes `window.canInstallPwa()` / `window.promptPwaInstall()`. The Dart bridge is in `lib/utils/pwa_install.dart` using a conditional import pattern (`pwa_install_web.dart` vs `pwa_install_stub.dart`) keyed on `dart.library.js_interop`.

## Organizer group editing

Organizers can edit a group after creation via the edit icon in `GroupDetailsPage`'s `AppBar` (`GroupService.update`). Editable: `description` ("about"), `budget`, `currency`, `event_date`. **`name` is immutable** — this is a deliberate scope decision, not a gap. `event_date` stays editable even after the draw; the day-before reminder system re-derives itself from the live `event_date` on every cron run (see `send-event-reminders` above), so rescheduling just follows naturally with no locking or manual re-sync needed.

## Navigation

Every non-root page (`sign_in_page.dart`, `create_group_page.dart`, `group_details_page.dart`, `participant_event_page.dart`, and all three `AppBar`s in `join_page.dart`) has an **explicit** `leading: IconButton(icon: Icons.arrow_back, onPressed: () => context.go('/'))` on its `AppBar`, rather than relying on Flutter's default `Navigator.canPop()`-driven back arrow. This matters specifically for Flutter web: a browser refresh (F5) clears the in-memory Navigator push stack entirely, which silently hides the automatic back arrow even on routes originally reached via `context.push()`. `context.go('/')` is the correct universal "home" target since `/` renders `_RootGate`, which shows the landing page or dashboard depending on auth state.

## Participant wishlist rules

- Participants can edit **only their own** wishlist (`updateMyWishlist` targets their own row; a DB trigger rejects changes to any other column).
- After the draw, a participant can see their giftee's wishlist **read-only** via `get_my_giftee` RPC. There is no edit UI for the giftee's wishlist.

## Sign-out behaviour

`_RootGate` in `lib/main.dart` listens directly to `AuthService.onAuthStateChange` via a `StreamSubscription` and calls `setState` on change. This is required because a same-path `context.go('/')` call after sign-out does not reliably trigger go_router to re-evaluate the route builder, causing the dashboard to remain visible for several seconds.

## Organizer joining their own event

On the group details page, an organizer can tap "Join as a participant too". This calls `joinAsAuthenticatedUser` with `userId: AuthService.currentUser!.id` and their account email. The app checks `_organizerIsParticipant` (matches by email) to only show this button once.

## Friendly error messages

`lib/utils/friendly_error.dart` translates raw `PostgrestException` / `AuthException` to plain language. Every `catch (e)` block in the UI must use `friendlyError(e)`, never `e.toString()` directly.

## Testing approach used in this project

Real bugs were found by running headless Chromium via Playwright against the **live production URL** with **real user JWTs** (not the service-role key, which bypasses RLS):
```bash
# Get a real JWT
curl -s "https://nwtbovavfvskhwpdglat.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"email":"...","password":"..."}' | python3 -m json.tool
```
Use the service-role key only for admin queries (reading all rows, deleting test data). Service-role bypasses all RLS and hides real permission bugs.

## What's not in the repo

- Netlify personal access token
- Supabase service-role key
- Gmail app password (stored as a Supabase secret, not locally)
- The `chanel/` legacy Flask app (separate directory, do not modify)
