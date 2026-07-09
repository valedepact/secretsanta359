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

## Draw algorithm

`lib/utils/draw_algorithm.dart`:
- Prefers cross-gender pairs (male→female, female→male).
- Falls back to random derangement if gender split is uneven.
- **2-cycles (mutual pairs, e.g. A→B and B→A) are explicitly rejected** — the algorithm retries up to 200 times to find a non-reciprocal arrangement. This was a real bug found in a production draw.

## Email edge functions

Both functions use `npm:nodemailer@6.9.16` with Gmail SMTP (port 465, SSL). **Do not switch to `denomailer` from deno.land/x** — it causes `BOOT_ERROR` in Supabase's Edge Runtime (confirmed by bisecting imports).

- `supabase/functions/send-reveal-emails/` — triggered after a draw, emails every participant their reveal code.
- `supabase/functions/notify-organizer-join/` — triggered when someone joins, emails the organizer.

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
