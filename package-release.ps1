[CmdletBinding()]
param(
    [string]$Tag = "v0.0.1-alpha"
)

$ErrorActionPreference = 'Stop'
$rootDir = $PSScriptRoot
$distDir = Join-Path $rootDir "dist"

if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$standardZipName = "D2Dawn-GUI-Installer-$Tag.zip"
$standardZipPath = Join-Path $distDir $standardZipName

$bundledZipName = "D2Dawn-GUI-Installer-$Tag-bundled.zip"
$bundledZipPath = Join-Path $distDir $bundledZipName

# Files to include in the release archives (explicitly excluding dawn-logo.png)
$baseFiles = @(
    "Install-Dawn-GUI.cmd",
    "Install-Dawn-GUI.ps1",
    "Download-DestinyBuild.cmd",
    "Download-DestinyBuild.ps1",
    "README-Installer.txt",
    "README.md",
    "LICENSE"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Packaging Dawn GUI Installer ($Tag)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Package Standard Release
Write-Host "`n[1/2] Creating $standardZipName..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $standardZipPath) {
    Remove-Item -LiteralPath $standardZipPath -Force
}

$tempStdDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempStdDir | Out-Null
try {
    foreach ($file in $baseFiles) {
        $src = Join-Path $rootDir $file
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $tempStdDir $file) -Force
        } else {
            Write-Warning "File not found: $src"
        }
    }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempStdDir, $standardZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
} finally {
    Remove-Item -LiteralPath $tempStdDir -Recurse -Force -ErrorAction SilentlyContinue
}

$hashStd = (Get-FileHash -LiteralPath $standardZipPath -Algorithm SHA256).Hash.ToLower()
$shaStdFile = "$standardZipPath.sha256"
Set-Content -LiteralPath $shaStdFile -Value "$hashStd  $standardZipName" -Encoding ASCII
Write-Host "  -> Created: $standardZipPath" -ForegroundColor Green
Write-Host "  -> SHA-256: $hashStd" -ForegroundColor Gray

# 2. Package Bundled Release (if upstream Dawn files exist)
$upstreamFiles = @("release.json", "Install-Dawn.ps1", "Install-Dawn.cmd", "READ-ME.txt")
$hasUpstream = (Test-Path (Join-Path $rootDir "release.json")) -and (Test-Path (Join-Path $rootDir "payload"))

if ($hasUpstream) {
    Write-Host "`n[2/2] Creating $bundledZipName..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $bundledZipPath) {
        Remove-Item -LiteralPath $bundledZipPath -Force
    }
    
    $tempBundleDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempBundleDir | Out-Null
    try {
        foreach ($file in $baseFiles) {
            $src = Join-Path $rootDir $file
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $tempBundleDir $file) -Force
            }
        }
        foreach ($file in $upstreamFiles) {
            $src = Join-Path $rootDir $file
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $tempBundleDir $file) -Force
            }
        }
        $payloadSrc = Join-Path $rootDir "payload"
        if (Test-Path -LiteralPath $payloadSrc) {
            Copy-Item -LiteralPath $payloadSrc -Destination (Join-Path $tempBundleDir "payload") -Recurse -Force
        }
        
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempBundleDir, $bundledZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    } finally {
        Remove-Item -LiteralPath $tempBundleDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $hashBundle = (Get-FileHash -LiteralPath $bundledZipPath -Algorithm SHA256).Hash.ToLower()
    $shaBundleFile = "$bundledZipPath.sha256"
    Set-Content -LiteralPath $shaBundleFile -Value "$hashBundle  $bundledZipName" -Encoding ASCII
    Write-Host "  -> Created: $bundledZipPath" -ForegroundColor Green
    Write-Host "  -> SHA-256: $hashBundle" -ForegroundColor Gray
}

Write-Host "`nRelease packaging completed successfully!" -ForegroundColor Green
