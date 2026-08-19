$mobileRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $mobileRoot)
$envPath = Join-Path $repoRoot ".env"

Set-Location -LiteralPath $mobileRoot

$defines = @{}
if (Test-Path -LiteralPath $envPath) {
    Get-Content -LiteralPath $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            return
        }
        $parts = $line.Split("=", 2)
        $defines[$parts[0].Trim()] = $parts[1].Trim()
    }
}

function Get-DefineValue($name, $fallback) {
    $processValue = [Environment]::GetEnvironmentVariable($name, "Process")
    # An explicitly empty process value is still an override. This lets a
    # caller clear a value from .env (especially Supabase credentials or the
    # Coach surface flag) without editing that file.
    if ($null -ne $processValue) {
        return $processValue
    }
    if ($defines.ContainsKey($name) -and $defines[$name].Length -gt 0) {
        return $defines[$name]
    }
    return $fallback
}

$appEnv = Get-DefineValue "APP_ENV" "development"
$flutterBin = Get-DefineValue "FLUTTER_BIN" "flutter"
$pythonBin = Get-DefineValue "PYTHON_BIN" "python"
$useMockData = Get-DefineValue "USE_MOCK_DATA" "true"
$supabaseUrl = Get-DefineValue "SUPABASE_URL" ""
$supabasePublishableKey = Get-DefineValue "SUPABASE_PUBLISHABLE_KEY" ""
$supabaseAnonKey = Get-DefineValue "SUPABASE_ANON_KEY" ""
$stagingSupabaseProjectRef = Get-DefineValue "STAGING_SUPABASE_PROJECT_REF" ""
$pilotSupabaseProjectRef = Get-DefineValue "PILOT_SUPABASE_PROJECT_REF" ""
$aiServiceBaseUrl = Get-DefineValue "AI_SERVICE_BASE_URL" "http://localhost:8000"
$coachSurfaceEnabled = Get-DefineValue "COACH_SURFACE_ENABLED" ""

# Frontend dependencies, the compiler, and the static server do not need
# backend-only credentials inherited from the caller's process environment.
Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
Remove-Item Env:SCHEDULED_REFRESH_TOKEN -ErrorAction SilentlyContinue

& $flutterBin pub get
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $flutterBin build web --debug --no-wasm-dry-run `
    --dart-define=APP_ENV=$appEnv `
    --dart-define=USE_MOCK_DATA=$useMockData `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_PUBLISHABLE_KEY=$supabasePublishableKey `
    --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey `
    --dart-define=STAGING_SUPABASE_PROJECT_REF=$stagingSupabaseProjectRef `
    --dart-define=PILOT_SUPABASE_PROJECT_REF=$pilotSupabaseProjectRef `
    --dart-define=AI_SERVICE_BASE_URL=$aiServiceBaseUrl `
    --dart-define=COACH_SURFACE_ENABLED=$coachSurfaceEnabled
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $pythonBin -m http.server 7357 --bind 127.0.0.1 --directory "build\web"
