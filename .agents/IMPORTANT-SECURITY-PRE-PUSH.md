# Important Security Pre-Push Checklist

This repository is public. Before any commit or push, especially after touching
auth, Supabase, Vercel, environment config, logs, docs, or agent notes, run a
security check and report the result.

## Never Commit

Do not commit any of these values, even in docs or `.agents/` notes:

- `.env`, `.env.local`, `.vercel/`, local credentials, or generated local config.
- Supabase `service_role` keys.
- Supabase `sb_secret_...` keys.
- Database passwords or full `postgresql://...` connection strings.
- OAuth client secrets.
- Private keys or certificates.
- API tokens, bearer tokens, session cookies, or JWTs.
- Real user data, emails from production data, logs with personal data, or
  screenshots containing private account details.

Frontend-safe values such as Supabase URLs, project refs, and anon/publishable
keys are not service secrets, but avoid writing concrete project refs or keys
into docs and agent notes unless the user explicitly asks. Prefer placeholders
such as:

```text
https://<project-ref>.supabase.co
<anon-or-publishable-key>
```

## Required Checks Before Commit Or Push

1. Confirm local secret files are not tracked:

```powershell
git ls-files .env .env.local .vercel
```

Expected output: empty.

2. Compare local `.env` Supabase values against tracked files without printing
the values:

```powershell
$envFile = '.env'
$tracked = git ls-files
$url = (Get-Content $envFile | Where-Object { $_ -like 'SUPABASE_URL=*' }).Split('=',2)[1]
$key = (Get-Content $envFile | Where-Object { $_ -like 'SUPABASE_ANON_KEY=*' }).Split('=',2)[1]
$urlHits = @()
$keyHits = @()
foreach ($f in $tracked) {
  if (Test-Path -LiteralPath $f) {
    $content = Get-Content -Raw -LiteralPath $f -ErrorAction SilentlyContinue
    if ($url -and $content.Contains($url)) { $urlHits += $f }
    if ($key -and $content.Contains($key)) { $keyHits += $f }
  }
}
"Exact local SUPABASE_URL hits in tracked files: $($urlHits.Count)"
$urlHits
"Exact local SUPABASE_ANON_KEY hits in tracked files: $($keyHits.Count)"
$keyHits
```

Expected result: both counts are `0`.

3. Scan for common secret markers, excluding ignored local/build files:

```powershell
rg -n "sb_secret_|service_role_key\s*[:=]|BEGIN .*PRIVATE KEY|client_secret\s*[:=]|DATABASE_URL=postgres|postgresql://|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" . --glob "!.env" --glob "!.env.local" --glob "!.vercel/**" --glob "!apps/mobile/build/**"
```

Expected result: no real secret values. Variable names alone, such as a config
field named `supabase_service_role_key`, are acceptable if no value is present.

4. Check the staged diff before committing:

```powershell
git diff --cached --check
git diff --cached --stat
git diff --cached
```

Read the staged diff for accidental literal keys, concrete private URLs,
project refs in docs, copied logs, screenshots, or generated files.

5. After committing and before pushing, repeat the exact local `.env` value
check against files in the last commit:

```powershell
$envFile = '.env'
$url = (Get-Content $envFile | Where-Object { $_ -like 'SUPABASE_URL=*' }).Split('=',2)[1]
$key = (Get-Content $envFile | Where-Object { $_ -like 'SUPABASE_ANON_KEY=*' }).Split('=',2)[1]
$commitFiles = git diff-tree --no-commit-id --name-only -r HEAD
$urlHits = @()
$keyHits = @()
foreach ($f in $commitFiles) {
  $content = git show "HEAD:$f" 2>$null
  $joined = [string]::Join("`n", $content)
  if ($url -and $joined.Contains($url)) { $urlHits += $f }
  if ($key -and $joined.Contains($key)) { $keyHits += $f }
}
"Exact local SUPABASE_URL hits in last commit files: $($urlHits.Count)"
$urlHits
"Exact local SUPABASE_ANON_KEY hits in last commit files: $($keyHits.Count)"
$keyHits
```

Expected result: both counts are `0`.

## If A Real Secret Is Found

Stop immediately. Do not push.

If it is already committed but not pushed, amend or reset the local commit to
remove it. If it was pushed to the public repository, treat it as compromised:
rotate or revoke the secret first, then decide whether a history rewrite and
GitHub support request are warranted.

## Reporting

In the final response after any commit/push, include a short security note:

```text
Security check: .env/.env.local/.vercel are untracked; exact local
SUPABASE_URL/SUPABASE_ANON_KEY hits in tracked files: 0/0; no real secret values
found.
```
