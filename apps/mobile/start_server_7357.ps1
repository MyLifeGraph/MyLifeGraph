$mobileRoot = "C:\Users\matze\Documents\New project 2\apps\mobile"
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

& flutter build web --debug --no-wasm-dry-run `
    --dart-define=APP_ENV=$(Get-DefineValue "APP_ENV" "development") `
    --dart-define=USE_MOCK_DATA=$(Get-DefineValue "USE_MOCK_DATA" "false") `
    --dart-define=SUPABASE_URL=$(Get-DefineValue "SUPABASE_URL" "") `
    --dart-define=SUPABASE_ANON_KEY=$(Get-DefineValue "SUPABASE_ANON_KEY" "") `
    --dart-define=AI_SERVICE_BASE_URL=$(Get-DefineValue "AI_SERVICE_BASE_URL" "http://localhost:8000")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& "C:\Users\matze\miniconda3\python.exe" -m http.server 7357 --bind 127.0.0.1 --directory "build\web"
