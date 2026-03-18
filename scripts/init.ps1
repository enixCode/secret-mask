# Scans protected files from .secretmask/config.json and generates .secretmask/secrets.map
# Usage: powershell -ExecutionPolicy Bypass -File init.ps1 -ProjectDir "C:\path\to\project"

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir
)

$configPath = Join-Path $ProjectDir ".secretmask\config.json"
$mapPath = Join-Path $ProjectDir ".secretmask\secrets.map"

if (-not (Test-Path $configPath)) {
    Write-Error "config.json not found at $configPath"
    Write-Host "Copy example/config.example.json to .secretmask/config.json in your project"
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$mappings = @()

foreach ($prop in $config.PSObject.Properties) {
    $filePattern = $prop.Name
    $rules = $prop.Value
    $keyPatterns = @()
    if ($rules.onlyKeys) {
        $keyPatterns = @($rules.onlyKeys)
    }

    $matchingFiles = Get-ChildItem -Path $ProjectDir -Filter $filePattern -ErrorAction SilentlyContinue

    foreach ($file in $matchingFiles) {
        $lines = Get-Content $file.FullName

        foreach ($line in $lines) {
            if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }

            if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.+)$') {
                $key = $matches[1]
                $value = $matches[2].Trim('"').Trim("'")

                if ([string]::IsNullOrEmpty($value)) { continue }

                $shouldMask = $false
                if ($keyPatterns.Count -eq 0) {
                    $shouldMask = $true
                } else {
                    $upperKey = $key.ToUpper()
                    foreach ($pattern in $keyPatterns) {
                        if ($upperKey -match $pattern) {
                            $shouldMask = $true
                            break
                        }
                    }
                }

                if ($shouldMask) {
                    $placeholder = "SECRET_" + $key.ToUpper()
                    $mappings += "$value`t$placeholder"
                }
            }
        }
    }
}

$mappings = $mappings | Select-Object -Unique

$secretmaskDir = Join-Path $ProjectDir ".secretmask"
if (-not (Test-Path $secretmaskDir)) {
    New-Item -ItemType Directory -Path $secretmaskDir | Out-Null
}

$mappings | Set-Content $mapPath -NoNewline:$false

# Add .secretmask to .gitignore if not already there
$gitignorePath = Join-Path $ProjectDir ".gitignore"
if (Test-Path $gitignorePath) {
    $gitignore = Get-Content $gitignorePath -Raw
    if ($gitignore -notmatch '\.secretmask') {
        Add-Content $gitignorePath "`n.secretmask/"
        Write-Host "Added .secretmask/ to .gitignore"
    }
} else {
    Set-Content $gitignorePath ".secretmask/`n"
    Write-Host "Created .gitignore with .secretmask/"
}

Write-Host "Generated $($mappings.Count) secret mappings in $mapPath"
