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

Both functions use `npm:nodemailer@6.9.16` with Gmail SMTP (port 465, SSL). **Do not switch to `denomailer` from deno.land/x** — it causes `BOOT_ERROR` in Supabase's Edge Runtime (confirmed by bisecting imports).

- `supabase/functions/send-reveal-emails/` — triggered after a draw (and after organizer-triggered latecomer pairings), emails participants their reveal code. Only emails rows where `assigned_to_id is not null and notified_at is null`, and sets `notified_at` after each successful send — this makes it safe to call repeatedly (e.g. after pairing latecomers) without re-emailing everyone. A full redraw resets `notified_at` to null for the whole group so everyone gets re-notified.
- `supabase/functions/notify-organizer-join/` — triggered when someone joins, emails the organizer.
- **Both functions must handle CORS explicitly**: `Deno.serve` needs to short-circuit `OPTIONS` preflight requests and attach `Access-Control-Allow-Origin` / `Access-Control-Allow-Headers` to every response (including error responses), or the browser blocks the call client-side (`net::ERR_FAILED`) before it reaches server code. This broke silently in both functions and was fixed by adding a shared `corsHeaders` object.

Also use `https://esm.sh/@supabase/supabase-js@2` (not `jsr:@supabase/supabase-js@2`) — the jsr: import also fails to boot.

## Android

- Application ID: `ug.secretsanta359.app` (in `android/app/build.gradle.kts` and `android/app/src/main/kotlin/ug/secretsanta359/app/MainActivity.kt`)
- **Do not change this back to `com.example.*`** — it causes silent install failures (signing certificate conflict) if any other Flutter template app is installed on the device.
- `.apk` files cannot be installed on iOS — this is a platform limitation, not a bug.

## PWA install

`web/index.html` captures the browser's `beforeinstallprompt` event and exposes `window.canInstallPwa()` / `window.promptPwaInstall()`. The Dart bridge is in `lib/utils/pwa_install.dart` using a conditional import pattern (`pwa_install_web.dart` vs `pwa_install_stub.dart`) keyed on `dart.library.js_interop`.

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
