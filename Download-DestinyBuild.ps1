#requires -Version 5.1
<#
.SYNOPSIS
    Downloads Destiny 2 Build 86657 via Steam DepotDownloader for Project Sunrise / Dawn.
.DESCRIPTION
    Automates the Steam depot download process described in:
    https://projectsunrise.dev/guides/installing/
    Downloads:
      - Depot 1085661 (Content, Manifest 7180122903232116872)
      - Depot 1085662 (Binaries, Manifest 2210332166360342287)
.PARAMETER Destination
    Target folder where the game build should be downloaded.
.PARAMETER SteamUsername
    Steam account username (required if not using -UseQrCode).
.PARAMETER UseQrCode
    Use Steam Mobile App QR code authentication instead of password.
.PARAMETER ContentOnly
    Download content depot only.
.PARAMETER BinariesOnly
    Download binaries depot only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $Destination,

    [Parameter(Mandatory = $false)]
    [string] $SteamUsername,

    [switch] $UseQrCode,
    [switch] $ContentOnly,
    [switch] $BinariesOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppId = '1085660'
$script:ContentDepot = '1085661'
$script:ContentManifest = '7180122903232116872'
$script:BinariesDepot = '1085662'
$script:BinariesManifest = '2210332166360342287'
$script:ExpectedFileVersion = '86657.20.08.23.1800.d2_rc'
$script:DepotDownloaderUrl = 'https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-windows-x64.zip'

function Get-DepotDownloaderPath {
    # 1. Local tools folder
    $localTool = Join-Path $PSScriptRoot 'tools\DepotDownloader\DepotDownloader.exe'
    if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }

    # 2. Local root
    $rootTool = Join-Path $PSScriptRoot 'DepotDownloader.exe'
    if (Test-Path -LiteralPath $rootTool -PathType Leaf) { return $rootTool }

    # 3. Check for zip in parent or local folder
    $zipCandidates = @(
        (Join-Path $PSScriptRoot '..\DepotDownloader-windows-x64.zip'),
        (Join-Path $PSScriptRoot 'DepotDownloader-windows-x64.zip')
    )
    foreach ($zip in $zipCandidates) {
        if (Test-Path -LiteralPath $zip -PathType Leaf) {
            Write-Host "Found DepotDownloader ZIP at $zip. Extracting..."
            $targetDir = Join-Path $PSScriptRoot 'tools\DepotDownloader'
            [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $targetDir)
            if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }
        }
    }

    # 4. PATH lookup
    $cmd = Get-Command 'DepotDownloader.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 5. Auto-download from GitHub
    Write-Host "DepotDownloader not found. Downloading from GitHub..."
    $toolsDir = Join-Path $PSScriptRoot 'tools\DepotDownloader'
    [System.IO.Directory]::CreateDirectory($toolsDir) | Out-Null
    $tempZip = Join-Path $toolsDir 'DepotDownloader.zip'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $script:DepotDownloaderUrl -OutFile $tempZip -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $toolsDir)
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }
    throw "Could not obtain DepotDownloader.exe. Please download DepotDownloader-windows-x64.zip into tools\DepotDownloader."
}

function Invoke-DepotDownload {
    if (-not $Destination) {
        $Destination = (Read-Host 'Destination folder for Destiny 2 build 86657').Trim('"')
    }

    $destPath = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $destPath)) {
        Write-Host "Creating destination directory: $destPath"
        [System.IO.Directory]::CreateDirectory($destPath) | Out-Null
    }

    # Check disk space (warn if < 100 GB)
    try {
        $root = [System.IO.Path]::GetPathRoot($destPath)
        $drive = New-Object System.IO.DriveInfo($root)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        Write-Host "Drive $root free space: $freeGB GB (recommended: 100 GB)"
        if ($freeGB -lt 80) {
            Write-Warning "Free space is low ($freeGB GB). A complete Destiny 2 build requires ~80-100 GB."
        }
    } catch {}

    $depotDownloaderExe = Get-DepotDownloaderPath
    Write-Host "Using DepotDownloader: $depotDownloaderExe"

    # Determine authentication args
    $authArgs = @()
    if ($UseQrCode) {
        $authArgs += "-qr"
        $authArgs += "-remember-password"
        Write-Host "Authentication: Steam Mobile App QR Code (-qr -remember-password)"
    } else {
        if (-not $SteamUsername) {
            $SteamUsername = (Read-Host 'Steam username (account that owns Destiny 2)').Trim()
        }
        if (-not $SteamUsername) {
            throw "Steam username is required when not using -UseQrCode."
        }
        $authArgs += @("-username", "$SteamUsername", "-remember-password")
        Write-Host "Authentication: Steam username '$SteamUsername' (-remember-password)"
    }

    # Common platform args
    $platformArgs = @("-os", "windows", "-osarch", "64")

    # Step 1: Content Depot (1085661)
    if (-not $BinariesOnly) {
        Write-Host "`n=======================================================" -ForegroundColor Cyan
        Write-Host "Step 1/2: Downloading Content Depot (Depot 1085661)" -ForegroundColor Cyan
        Write-Host "Manifest: $script:ContentManifest"
        Write-Host "Destination: $destPath"
        Write-Host "=======================================================`n" -ForegroundColor Cyan

        $depot1Args = @(
            "-app", $script:AppId,
            "-depot", $script:ContentDepot,
            "-manifest", $script:ContentManifest,
            "-dir", "`"$destPath`""
        ) + $authArgs + $platformArgs

        Write-Host "Running: & DepotDownloader.exe $($depot1Args -join ' ')"
        $proc1 = Start-Process -FilePath $depotDownloaderExe -ArgumentList ($depot1Args -join ' ') -Wait -PassThru -NoNewWindow
        if ($proc1.ExitCode -ne 0) {
            throw "Depot 1085661 download failed with exit code $($proc1.ExitCode)."
        }
        Write-Host "`nContent Depot (1085661) completed successfully!" -ForegroundColor Green
    }

    # Step 2: Binaries Depot (1085662)
    if (-not $ContentOnly) {
        Write-Host "`n=======================================================" -ForegroundColor Cyan
        Write-Host "Step 2/2: Downloading Binaries Depot (Depot 1085662)" -ForegroundColor Cyan
        Write-Host "Manifest: $script:BinariesManifest"
        Write-Host "Destination: $destPath"
        Write-Host "=======================================================`n" -ForegroundColor Cyan

        # Reuses saved credentials in destination\.DepotDownloader
        $depot2Auth = @("-remember-password")
        if (-not $UseQrCode -and $SteamUsername) {
            $depot2Auth = @("-username", "$SteamUsername", "-remember-password")
        }

        $depot2Args = @(
            "-app", $script:AppId,
            "-depot", $script:BinariesDepot,
            "-manifest", $script:BinariesManifest,
            "-dir", "`"$destPath`""
        ) + $depot2Auth + $platformArgs

        Write-Host "Running: & DepotDownloader.exe $($depot2Args -join ' ')"
        $proc2 = Start-Process -FilePath $depotDownloaderExe -ArgumentList ($depot2Args -join ' ') -Wait -PassThru -NoNewWindow
        if ($proc2.ExitCode -ne 0) {
            throw "Depot 1085662 download failed with exit code $($proc2.ExitCode)."
        }
        Write-Host "`nBinaries Depot (1085662) completed successfully!" -ForegroundColor Green
    }

    # Verification
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "Verifying downloaded game build..." -ForegroundColor Cyan
    $exePath = Join-Path $destPath 'destiny2.exe'
    if (Test-Path -LiteralPath $exePath -PathType Leaf) {
        $version = (Get-Item -LiteralPath $exePath).VersionInfo.FileVersion
        if ($version -eq $script:ExpectedFileVersion) {
            Write-Host "VERIFIED: Destiny 2 build $version found in $destPath!" -ForegroundColor Green
            Write-Host "You can now run Install-Dawn.cmd or Install-Dawn-GUI.cmd targeting this directory." -ForegroundColor Green
        } else {
            Write-Warning "destiny2.exe has version $version, expected $script:ExpectedFileVersion."
        }
    } else {
        Write-Warning "destiny2.exe was not found in $destPath. The download may be incomplete."
    }
    Write-Host "=======================================================`n" -ForegroundColor Cyan
}

Invoke-DepotDownload
