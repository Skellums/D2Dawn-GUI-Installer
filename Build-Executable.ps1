#requires -Version 5.1
<#
.SYNOPSIS
    Compiles the Dawn GUI Installer into a standalone Windows executable (.exe).
.DESCRIPTION
    Uses ps2exe and the Windows built-in C# compiler to generate a true Win32 GUI
    single-file executable (DawnInstaller.exe) with embedded icon, STA mode, DPI
    awareness, and embedded companion downloader scripts.
.PARAMETER OutputPath
    Target destination for the compiled executable. Defaults to 'dist\DawnInstaller.exe'.
.PARAMETER SkipIcon
    Skip generating/embedding the application icon.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [string]$Version,

    [switch]$SkipIcon
)

$ErrorActionPreference = 'Stop'
$rootDir = $PSScriptRoot
$distDir = Join-Path $rootDir 'dist'
$assetsDir = Join-Path $rootDir 'assets'

if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $distDir 'DawnInstaller.exe'
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Building Standalone Dawn GUI Executable   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Generate multi-resolution ICO from PNG if needed
$icoPath = Join-Path $assetsDir 'dawn.ico'
$pngPath = Join-Path $assetsDir 'dawndownload-logo.png'

if (-not $SkipIcon) {
    if (-not (Test-Path -LiteralPath $icoPath) -and (Test-Path -LiteralPath $pngPath)) {
        Write-Host "`n[1/3] Generating multi-resolution icon ($icoPath)..." -ForegroundColor Yellow
        Add-Type -AssemblyName System.Drawing
        $bmp = [System.Drawing.Bitmap]::FromFile($pngPath)
        $sizes = @(256, 128, 64, 48, 32, 16)
        $msList = New-Object System.Collections.Generic.List[byte[]]

        foreach ($sz in $sizes) {
            $resized = New-Object System.Drawing.Bitmap($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($resized)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($bmp, 0, 0, $sz, $sz)
            $g.Dispose()

            $ms = New-Object System.IO.MemoryStream
            $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $msList.Add($ms.ToArray())
            $ms.Dispose()
            $resized.Dispose()
        }
        $bmp.Dispose()

        $fs = [System.IO.File]::Create($icoPath)
        $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([uint16]0)
        $bw.Write([uint16]1)
        $bw.Write([uint16]$sizes.Count)

        $offset = 6 + (16 * $sizes.Count)
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $sz = $sizes[$i]
            $b = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
            $len = $msList[$i].Length
            $bw.Write($b)
            $bw.Write($b)
            $bw.Write([byte]0)
            $bw.Write([byte]0)
            $bw.Write([uint16]1)
            $bw.Write([uint16]32)
            $bw.Write([uint32]$len)
            $bw.Write([uint32]$offset)
            $offset += $len
        }
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $bw.Write($msList[$i])
        }
        $bw.Dispose()
        $fs.Dispose()
        Write-Host "  -> Icon generated successfully." -ForegroundColor Green
    } else {
        Write-Host "`n[1/3] Using existing icon: $icoPath" -ForegroundColor Gray
    }
} else {
    $icoPath = $null
}

# 2. Ensure ps2exe is available
Write-Host "`n[2/3] Checking ps2exe compilation module..." -ForegroundColor Yellow
if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing ps2exe from PSGallery (CurrentUser scope)..." -ForegroundColor Cyan
    Install-Module -Name ps2exe -Scope CurrentUser -Force -SkipPublisherCheck
}

# 3. Compile standalone executable
$inputScript = Join-Path $rootDir 'Install-Dawn-GUI.ps1'
$downloaderScript = Join-Path $rootDir 'Download-DestinyBuild.ps1'

if (-not $Version) {
    if (Test-Path -LiteralPath $inputScript) {
        $guiContent = Get-Content -LiteralPath $inputScript -Raw
        if ($guiContent -match '\$script:GuiVersion\s*=\s*[''"]([^''"]+)[''"]') {
            $Version = $matches[1].Trim()
        }
    }
    if (-not $Version) { $Version = '0.0.3' }
}

$rawVer = $Version.TrimStart('v').Trim()
$parts = $rawVer.Split('.')
$quadList = New-Object System.Collections.Generic.List[string]
foreach ($p in $parts) { $quadList.Add($p) }
while ($quadList.Count -lt 4) { $quadList.Add('0') }
$quadVersion = ($quadList[0..3] -join '.')

Write-Host "`n[3/3] Compiling $inputScript -> $OutputPath (v$rawVer / $quadVersion)..." -ForegroundColor Yellow

$ps2exeParams = @{
    inputFile   = $inputScript
    outputFile  = $OutputPath
    noConsole   = $true
    STA         = $true
    x64         = $true
    DPIAware    = $true
    supportOS   = $true
    title       = "Dawn GUI Installer"
    description = "Dawn GUI Installer & Steam Depot Downloader for Destiny 2 Build 86657"
    company     = "Project Sunrise / Dawn Community"
    product     = "Dawn Installer"
    copyright   = "GNU General Public License v3.0"
    version     = $quadVersion
}

if ($icoPath -and (Test-Path -LiteralPath $icoPath)) {
    $ps2exeParams['iconFile'] = $icoPath
}

if (Test-Path -LiteralPath $downloaderScript) {
    $ps2exeParams['embedFiles'] = @{ '%TEMP%\Download-DestinyBuild.ps1' = $downloaderScript }
}

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
}

Invoke-ps2exe @ps2exeParams

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "Compilation failed: Output executable was not generated at $OutputPath"
}

$fileItem = Get-Item -LiteralPath $OutputPath
$fileSizeKb = [math]::Round($fileItem.Length / 1KB, 1)
$sha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLower()

$shaFile = "$OutputPath.sha256"
Set-Content -LiteralPath $shaFile -Value "$sha256  $([System.IO.Path]::GetFileName($OutputPath))" -Encoding ASCII

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " Executable Compiled Successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  -> Executable: $OutputPath ($fileSizeKb KB)" -ForegroundColor Green
Write-Host "  -> SHA-256:    $sha256" -ForegroundColor Gray
Write-Host "  -> Checksum:   $shaFile" -ForegroundColor Gray
