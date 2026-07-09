# Vercel Flutter Supabase Google OAuth

## Problem

The Vercel-deployed Flutter Web app showed this user-facing error when clicking
**Sign in with Google**:

```text
Google sign-in could not start. Check Supabase OAuth settings.
```

The affected production URL was:

```text
https://my-life-graph.vercel.app/#/auth
```

Locally, Supabase Google OAuth had worked before. Supabase Google Provider,
Google Cloud redirect URI, Google JavaScript origin, and Supabase redirect URL
settings had already been checked.

## Root Cause

The Flutter Web production bundle did not contain the Supabase URL/key at all.
The deployed `main.dart.js` initially had no `supabase.co`, `auth/v1`, or
project ref string.

Vercel had these env vars set:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

Flutter does not automatically read `VITE_*` or `NEXT_PUBLIC_*` variables.
This app reads config at compile time through Dart defines:

```dart
String.fromEnvironment('SUPABASE_URL')
String.fromEnvironment('SUPABASE_ANON_KEY')
```

Without matching `--dart-define` values, `AppConfig.isSupabaseConfigured` was
false, `supabaseClientProvider` returned `null`, and the Google sign-in path
threw before starting OAuth.

## Relevant Code Paths

- `apps/mobile/lib/core/config/app_config.dart`
  - Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` with `String.fromEnvironment`.
- `apps/mobile/lib/core/bootstrap/app_bootstrap.dart`
  - Calls `Supabase.initialize(...)` only when both values are non-empty.
- `apps/mobile/lib/core/supabase/supabase_providers.dart`
  - Returns `null` when Supabase is not configured.
- `apps/mobile/lib/features/auth/presentation/providers/auth_providers.dart`
  - Throws `StateError('Supabase is not configured.')` when Google sign-in is
    attempted without a repository/client.
- `apps/mobile/lib/features/auth/data/auth_repository.dart`
  - Starts OAuth with:

```dart
_client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: kIsWeb ? Uri.base.origin : null,
);
```

## Fix Applied

Vercel environment variables were updated for the `my-life-graph` project:

```text
SUPABASE_URL       Production, Preview
SUPABASE_ANON_KEY  Production, Preview
```

The build script was also made resilient to common frontend env names:

```text
SUPABASE_URL
VITE_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_URL

SUPABASE_ANON_KEY
SUPABASE_PUBLISHABLE_KEY
VITE_SUPABASE_ANON_KEY
NEXT_PUBLIC_SUPABASE_ANON_KEY
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

These are normalized in `scripts/vercel_build.sh` and passed into Flutter via:

```bash
--dart-define=SUPABASE_URL="${RESOLVED_SUPABASE_URL}"
--dart-define=SUPABASE_ANON_KEY="${RESOLVED_SUPABASE_ANON_KEY}"
```

The script logs one of these messages during Vercel builds:

```text
Supabase config detected for Flutter build.
Supabase config missing for Flutter build; auth providers will be disabled.
```

## Verification Performed

After redeploying commit `e75b3f6`, Vercel build logs showed:

```text
Supabase config detected for Flutter build.
```

The live production bundle contained:

```text
https://<project-ref>.supabase.co
/auth/v1
provider=google
```

Direct Supabase OAuth authorize check returned `302 Found` to Google:

```text
https://<project-ref>.supabase.co/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2Fmy-life-graph.vercel.app
```

Browser verification on:

```text
https://my-life-graph.vercel.app/#/auth
```

confirmed that clicking **Sign in with Google** navigated to:

```text
https://accounts.google.com/...
```

with:

```text
redirect_uri=https://<project-ref>.supabase.co/auth/v1/callback
```

## Important Notes

- The working Supabase project ref should be read from local `.env`, Vercel env,
  or the live JS bundle. Do not rely on a pasted value when debugging OAuth.

- During the original debugging session, two similar-looking project refs were
  mentioned. Treat local `.env` / Vercel env values as the source of truth
  unless the user explicitly confirms a project migration.

- Do not put service-role or secret Supabase keys in Flutter Web. Only use the
  public anon/publishable key.

## Quick Debug Checklist

1. Check Vercel env names:

```bash
npx --yes vercel@latest env ls --scope matooo3s-projects
```

2. Inspect the latest Vercel deployment logs:

```bash
npx --yes vercel@latest inspect <deployment-url> --logs --scope matooo3s-projects
```

3. Confirm the build log says:

```text
Supabase config detected for Flutter build.
```

4. Download or inspect the live JS bundle and search for:

```text
supabase.co
auth/v1
google
```

5. Check Supabase OAuth starts:

```bash
curl -s -D - -o NUL --max-redirs 0 \
  -H "apikey: <anon-or-publishable-key>" \
  "https://<project-ref>.supabase.co/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2Fmy-life-graph.vercel.app"
```

Expected result: `302 Found` with `Location: https://accounts.google.com/...`.

6. In the browser, open:

```text
https://my-life-graph.vercel.app/#/auth
```

Click **Sign in with Google**. The app should leave Vercel and navigate to
Google Accounts.

## Redirects To Localhost After Google

If Google account selection succeeds but the final redirect goes to
`localhost:3000`, the likely cause is Supabase Auth URL Configuration rather
than Vercel:

- Supabase `Site URL` may still be `http://localhost:3000`.
- The `redirectTo` value passed by Flutter may not exactly match the Redirect
  URLs allow list.

The Flutter app should pass the current browser origin with a trailing slash:

```dart
redirectTo: kIsWeb ? webOAuthRedirectTo(Uri.base) : null
```

Expected values:

```text
https://my-life-graph.vercel.app/
http://127.0.0.1:7357/
http://localhost:7357/
```

For the remote Supabase project, configure Auth URL settings like this:

```text
Site URL:
https://my-life-graph.vercel.app/

Redirect URLs:
https://my-life-graph.vercel.app/
https://my-life-graph.vercel.app/**
http://127.0.0.1:7357/
http://127.0.0.1:7357/**
http://localhost:7357/
http://localhost:7357/**
```
