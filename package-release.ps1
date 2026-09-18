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

# Clean up any leftover bundled archives if present
Get-ChildItem -Path $distDir -Filter "*bundled*" -File -ErrorAction SilentlyContinue | Remove-Item -Force

$zipName = "D2Dawn-GUI-Installer-$Tag.zip"
$zipPath = Join-Path $distDir $zipName

# Files to include in the release archive: installer scripts & documentation only.
# Explicitly excludes binaries, depotdownloader, upstream game payloads, and logo assets.
$releaseFiles = @(
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

Write-Host "`nCreating $zipName..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    foreach ($file in $releaseFiles) {
        $src = Join-Path $rootDir $file
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $tempDir $file) -Force
            Write-Host "  + $file" -ForegroundColor Gray
        } else {
            Write-Warning "File not found: $src"
        }
    }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
$shaFile = "$zipPath.sha256"
Set-Content -LiteralPath $shaFile -Value "$hash  $zipName" -Encoding ASCII

Write-Host "`nPackage created successfully!" -ForegroundColor Green
Write-Host "  -> Archive: $zipPath" -ForegroundColor Green
Write-Host "  -> SHA-256: $hash" -ForegroundColor Gray
Write-Host "  -> Checksum file: $shaFile" -ForegroundColor Gray
