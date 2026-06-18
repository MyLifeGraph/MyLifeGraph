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
$supabaseAnonKey = Get-DefineValue "SUPABASE_ANON_KEY" ""
$aiServiceBaseUrl = Get-DefineValue "AI_SERVICE_BASE_URL" "http://localhost:8000"

& $flutterBin pub get
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $flutterBin build web --debug --no-wasm-dry-run `
    --dart-define=APP_ENV=$appEnv `
    --dart-define=USE_MOCK_DATA=$useMockData `
    --dart-define=SUPABASE_URL=$supabaseUrl `
    --dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey `
    --dart-define=AI_SERVICE_BASE_URL=$aiServiceBaseUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $pythonBin -m http.server 7357 --bind 127.0.0.1 --directory "build\web"
