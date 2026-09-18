#requires -Version 5.1
<#
.SYNOPSIS
    Visual WPF Graphical User Interface for Dawn Installer & Steam Depot Downloader.
.DESCRIPTION
    Provides an interactive, dark-themed GUI wrapper for Install-Dawn.ps1, with
    built-in Steam DepotDownloader integration to acquire Destiny 2 build 86657.
    Supports real-time output streaming, automated game root detection,
    pre-flight version validation, backup history browsing, one-click rollback,
    and simulation (-WhatIf) mode.
#>

# Ensure Single-Thread Apartment (STA) mode for WPF
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$scriptPath`""
        return
    }
}

# Resolve script directory reliably in all execution contexts
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
                    elseif ($PSCommandPath) { [System.IO.Path]::GetDirectoryName($PSCommandPath) }
                    elseif ($MyInvocation.MyCommand.Path) { [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path) }
                    else { (Get-Location).Path }

# Load WPF and compression assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xml, System.IO.Compression.FileSystem

$script:ReleaseManifestPath  = Join-Path $script:ScriptDir 'release.json'
$script:InstallerScriptPath  = Join-Path $script:ScriptDir 'Install-Dawn.ps1'
$script:DownloadScriptPath   = Join-Path $script:ScriptDir 'Download-DestinyBuild.ps1'
$script:ExpectedFileVersion  = '86657.20.08.23.1800.d2_rc'
$script:SettingsFile         = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DawnInstaller\settings.json'
$script:DepotDownloaderUrl   = 'https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-windows-x64.zip'

# --- Configuration Persistence ---
function Get-SavedSettings {
    try {
        if (Test-Path -LiteralPath $script:SettingsFile) {
            $content = Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json
            return $content
        }
    } catch {}
    return $null
}

function Save-UserSettings([string] $GameRoot, [string] $DownloadDir, [string] $SteamUser) {
    try {
        $dir = [System.IO.Path]::GetDirectoryName($script:SettingsFile)
        if (-not (Test-Path -LiteralPath $dir)) {
            [System.IO.Directory]::CreateDirectory($dir) | Out-Null
        }
        $obj = [ordered]@{
            LastGameRoot    = $GameRoot
            LastDownloadDir = $DownloadDir
            LastSteamUser   = $SteamUser
        }
        $json = ConvertTo-Json -InputObject $obj -Compress
        [System.IO.File]::WriteAllText($script:SettingsFile, $json, [System.Text.Encoding]::UTF8)
    } catch {}
}

# --- Game Directory Auto-Detection ---
function Find-DestinyGameDirectory {
    $candidates = New-Object System.Collections.Generic.List[string]

    $saved = Get-SavedSettings
    if ($saved -and $saved.PSObject.Properties['LastGameRoot'] -and $saved.LastGameRoot) {
        $candidates.Add($saved.LastGameRoot)
    }

    $candidates.Add((Join-Path $script:ScriptDir '..\Sunrise'))
    $candidates.Add((Join-Path $script:ScriptDir '..\Destiny 2'))
    $candidates.Add((Join-Path $script:ScriptDir '..\Destiny2'))
    $candidates.Add((Join-Path $script:ScriptDir '..'))

    try {
        $steamKey = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue
        if ($steamKey -and $steamKey.SteamPath) {
            $steamRoot = $steamKey.SteamPath
            $candidates.Add((Join-Path $steamRoot 'steamapps\common\Destiny 2'))

            $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                $content = Get-Content -LiteralPath $vdf -Raw
                $regexMatches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
                foreach ($m in $regexMatches) {
                    $libPath = $m.Groups[1].Value.Replace('\\', '\')
                    $candidates.Add((Join-Path $libPath 'steamapps\common\Destiny 2'))
                }
            }
        }
    } catch {}

    foreach ($drive in @('C', 'D', 'E', 'F', 'G', 'W')) {
        $candidates.Add("$drive`:\Games\Destiny 2")
        $candidates.Add("$drive`:\Games\Sunrise")
        $candidates.Add("$drive`:\Program Files (x86)\Steam\steamapps\common\Destiny 2")
    }

    foreach ($path in $candidates) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try {
            $resolved = [System.IO.Path]::GetFullPath($path).TrimEnd('\', '/')
            $exe = Join-Path $resolved 'destiny2.exe'
            if (Test-Path -LiteralPath $exe -PathType Leaf) {
                $ver = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
                if ($ver -eq $script:ExpectedFileVersion) {
                    return $resolved
                }
            }
        } catch {}
    }
    return $null
}

# --- DepotDownloader Tool Finder / Extractor ---
function Find-DepotDownloaderExe {
    $localTool = Join-Path $script:ScriptDir 'tools\DepotDownloader\DepotDownloader.exe'
    if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }

    $rootTool = Join-Path $script:ScriptDir 'DepotDownloader.exe'
    if (Test-Path -LiteralPath $rootTool -PathType Leaf) { return $rootTool }

    $zipCandidates = @(
        (Join-Path $script:ScriptDir '..\DepotDownloader-windows-x64.zip'),
        (Join-Path $script:ScriptDir 'DepotDownloader-windows-x64.zip')
    )
    foreach ($zip in $zipCandidates) {
        if (Test-Path -LiteralPath $zip -PathType Leaf) {
            try {
                $targetDir = Join-Path $script:ScriptDir 'tools\DepotDownloader'
                [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $targetDir)
                if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }
            } catch {}
        }
    }

    $cmd = Get-Command 'DepotDownloader.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

# --- XAML Definition ---
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dawn Installer &amp; Steam Downloader - Destiny 2"
        Height="730" Width="960" MinHeight="660" MinWidth="850"
        WindowStartupLocation="CenterScreen"
        Background="#12151B" Foreground="#E2E8F0"
        FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Modern ScrollViewer / ScrollBar styling -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#4B5563"/>
        </Style>

        <!-- Tab Item Style -->
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="BorderThickness" Value="0,0,0,2"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}" Margin="0,0,6,0" CornerRadius="4,4,0,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#1E232D"/>
                                <Setter TargetName="Border" Property="BorderBrush" Value="#E5A93C"/>
                                <Setter Property="Foreground" Value="#F8FAFC"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#1A1F28"/>
                                <Setter Property="Foreground" Value="#F1F5F9"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Standard Button Style -->
        <Style x:Key="StandardBtn" TargetType="Button">
            <Setter Property="Background" Value="#252C37"/>
            <Setter Property="Foreground" Value="#F1F5F9"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="BorderBrush" Value="#384252"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#323B4A"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#4B586E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#1B212A"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Accent Button Style -->
        <Style x:Key="PrimaryBtn" TargetType="Button">
            <Setter Property="Background" Value="#E5A93C"/>
            <Setter Property="Foreground" Value="#0F1115"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="pBorder" Background="{TemplateBinding Background}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="pBorder" Property="Background" Value="#F5B94E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="pBorder" Property="Background" Value="#D4992C"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="pBorder" Property="Opacity" Value="0.4"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger / Recovery Button Style -->
        <Style x:Key="DangerBtn" TargetType="Button">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="dBorder" Background="{TemplateBinding Background}"
                                CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="dBorder" Property="Background" Value="#EF4444"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="dBorder" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="dBorder" Property="Opacity" Value="0.4"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Header -->
            <RowDefinition Height="*"/>    <!-- Content Tabs -->
            <RowDefinition Height="Auto"/> <!-- Footer / Status Bar -->
        </Grid.RowDefinitions>

        <!-- HEADER BANNER -->
        <Border Grid.Row="0" Background="#181C23" BorderBrush="#262D38" BorderThickness="0,0,0,1" Padding="20,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Icon Emblem -->
                <Border Grid.Column="0" Width="44" Height="44" Background="#232935" BorderBrush="#E5A93C" BorderThickness="1.5" CornerRadius="8" Margin="0,0,16,0">
                    <TextBlock Text="&#x25C6;" Foreground="#E5A93C" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>

                <!-- Title & Release Subtitle -->
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="DAWN INSTALLER" FontSize="20" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,10,0"/>
                        <Border Background="#2C3442" CornerRadius="4" Padding="6,2" VerticalAlignment="Center">
                            <TextBlock Name="HeaderReleaseBadge" Text="v..." FontSize="11" FontWeight="SemiBold" Foreground="#E5A93C"/>
                        </Border>
                    </StackPanel>
                    <TextBlock Text="Destiny 2 Build 86657 &#x2022; Release Deployer &amp; Steam Depot Downloader" FontSize="12" Foreground="#94A3B8" Margin="0,3,0,0"/>
                </StackPanel>

                <!-- Header Action: Launch Game -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Name="BtnLaunchGame" Style="{StaticResource StandardBtn}" Content="&#x25B6; Launch Destiny 2" ToolTip="Launch destiny2.exe in selected game folder" Margin="0,0,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN TAB CONTROL -->
        <TabControl Name="MainTabs" Grid.Row="1" Background="Transparent" BorderThickness="0" Margin="16,12,16,8">

            <!-- TAB 1: INSTALL -->
            <TabItem Name="TabInstall" Header="Install Dawn">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="4,10,4,10">

                        <!-- INTERRUPTED INSTALL ALERT -->
                        <Border Name="AlertInterruptedBox" Visibility="Collapsed" Background="#3B1C1C" BorderBrush="#DC2626" BorderThickness="1" CornerRadius="6" Padding="16,12" Margin="0,0,0,14">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="&#x26A0; Interrupted Installation Detected!" FontWeight="Bold" FontSize="14" Foreground="#FCA5A5"/>
                                    <TextBlock Name="AlertInterruptedText" Text="A previous installation was interrupted and must be recovered before proceeding." FontSize="12" Foreground="#FEE2E2" Margin="0,3,0,0" TextWrapping="Wrap"/>
                                </StackPanel>
                                <Button Name="BtnRecoverInterrupted" Grid.Column="1" Style="{StaticResource DangerBtn}" Content="Recover / Rollback Now" VerticalAlignment="Center" Margin="12,0,0,0"/>
                            </Grid>
                        </Border>

                        <!-- NEED GAME DOWNLOAD CALLOUT -->
                        <Border Name="BannerNeedDownload" Visibility="Collapsed" Background="#1A2533" BorderBrush="#3B82F6" BorderThickness="1" CornerRadius="6" Padding="14,10" Margin="0,0,0,14">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                    <TextBlock Text="Need Destiny 2 Build 86657?" FontWeight="Bold" FontSize="13" Foreground="#93C5FD"/>
                                    <TextBlock Text="You can download the exact required Destiny 2 build directly from Steam using the built-in Depot Downloader." FontSize="11.5" Foreground="#BFDBFE" Margin="0,2,0,0"/>
                                </StackPanel>
                                <Button Name="BtnGoToDownloadTab" Grid.Column="1" Style="{StaticResource StandardBtn}" Content="Open Steam Downloader &#x2192;" VerticalAlignment="Center" Margin="10,0,0,0"/>
                            </Grid>
                        </Border>

                        <!-- CARD 1: GAME ROOT SELECTOR -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="DESTINY 2 GAME FOLDER" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,6"/>
                                <TextBlock Text="Select the folder containing destiny2.exe (Destiny 2 build 86657.20.08.23.1800.d2_rc)" FontSize="12" Foreground="#64748B" Margin="0,0,0,10"/>

                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>

                                    <TextBox Name="TxtGameRoot" Grid.Column="0" Background="#12151B" Foreground="#F8FAFC" BorderBrush="#384252" BorderThickness="1" FontSize="13" Padding="10,8" VerticalContentAlignment="Center" Margin="0,0,8,0"/>
                                    <Button Name="BtnBrowse" Grid.Column="1" Style="{StaticResource StandardBtn}" Content="Browse..." Margin="0,0,8,0"/>
                                    <Button Name="BtnAutoDetect" Grid.Column="2" Style="{StaticResource StandardBtn}" Content="Auto-Detect"/>
                                </Grid>

                                <!-- Game Validation Status Pill -->
                                <Border Name="GameStatusBorder" Background="#1B2822" BorderBrush="#22C55E" BorderThickness="1" CornerRadius="5" Padding="10,6" HorizontalAlignment="Left">
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Name="GameStatusIcon" Text="&#x2713;" FontWeight="Bold" Foreground="#22C55E" Margin="0,0,6,0"/>
                                        <TextBlock Name="GameStatusText" Text="Valid Destiny 2 build found" FontSize="12" Foreground="#86EFAC"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- CARD 2: RELEASE MANIFEST DETAILS -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="PACKAGE &amp; RELEASE INFORMATION" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,10"/>

                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="140"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Dawn Release:" Foreground="#64748B" FontSize="12" Margin="0,0,0,6"/>
                                    <TextBlock Name="LblReleaseVer" Grid.Row="0" Grid.Column="1" Text="..." Foreground="#F1F5F9" FontSize="12" FontWeight="SemiBold"/>

                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Target Build:" Foreground="#64748B" FontSize="12" Margin="0,0,0,6"/>
                                    <TextBlock Name="LblTargetBuild" Grid.Row="1" Grid.Column="1" Text="86657 (Destiny 2)" Foreground="#F1F5F9" FontSize="12"/>

                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Payload Files:" Foreground="#64748B" FontSize="12" Margin="0,0,0,6"/>
                                    <TextBlock Name="LblPayloadCount" Grid.Row="2" Grid.Column="1" Text="... items" Foreground="#F1F5F9" FontSize="12"/>

                                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Display Default:" Foreground="#64748B" FontSize="12"/>
                                    <TextBlock Grid.Row="3" Grid.Column="1" Text="Windowed Fullscreen (resolution &amp; settings kept)" Foreground="#F1F5F9" FontSize="12"/>
                                </Grid>

                                <Border Background="#13161C" CornerRadius="5" Padding="12,10" Margin="0,6,0,0">
                                    <TextBlock Text="Notice: Every installation starts a fresh profile using release defaults. Old Dawn saves and DLLs are backed up. Your existing Sunrise/Restoration directories are untouched." FontSize="11.5" Foreground="#94A3B8" TextWrapping="Wrap"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- CARD 3: ACTIONS & EXECUTION -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>

                                    <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                        <CheckBox Name="ChkWhatIf" Content="Dry Run / Simulation Mode (-WhatIf: preview changes without writing files)" Foreground="#CBD5E1" FontSize="12.5" Margin="0,0,0,6"/>
                                        <TextBlock Text="Simulates preflight, hashes, display config, and file operations safely." FontSize="11" Foreground="#64748B"/>
                                    </StackPanel>

                                    <Button Name="BtnInstall" Grid.Column="1" Style="{StaticResource PrimaryBtn}" Content="Install Dawn" MinWidth="180" Height="42" VerticalAlignment="Center"/>
                                </Grid>

                                <!-- Progress indicator bar -->
                                <StackPanel Name="ProgressContainer" Visibility="Collapsed" Margin="0,16,0,0">
                                    <Grid Margin="0,0,0,6">
                                        <TextBlock Name="TxtProgressStatus" Text="Running installer..." FontSize="12" Foreground="#E5A93C" FontWeight="SemiBold"/>
                                    </Grid>
                                    <ProgressBar Name="InstallProgressBar" Height="6" Background="#262D38" Foreground="#E5A93C" BorderThickness="0" IsIndeterminate="True"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: DOWNLOAD GAME BUILD (STEAM DEPOT DOWNLOADER) -->
            <TabItem Name="TabDownload" Header="Download Game Build">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="4,10,4,10">

                        <!-- HEADER CARD -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="STEAM DEPOT DOWNLOADER (DESTINY 2 BUILD 86657)" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,6"/>
                                <TextBlock Text="Downloads the clean vanilla Destiny 2 build 86657.20.08.23.1800.d2_rc directly from Steam via DepotDownloader. Destiny 2 is free on Steam, but an account that owns the game license is required." FontSize="12" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,10"/>

                                <Border Background="#13161C" CornerRadius="5" Padding="12,8">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Depots: 1085661 (Content, ~75 GB) + 1085662 (Binaries, ~50 MB) &#x2022; Requires ~80-100 GB storage" FontSize="11.5" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <Border Name="ToolStatusPill" Grid.Column="1" Background="#14532D" CornerRadius="4" Padding="8,3">
                                            <TextBlock Name="ToolStatusText" Text="&#x2713; DepotDownloader Ready" FontSize="11" FontWeight="SemiBold" Foreground="#86EFAC"/>
                                        </Border>
                                    </Grid>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- TARGET DIRECTORY & DISK SPACE -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="TARGET INSTALLATION DIRECTORY" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,6"/>
                                <TextBlock Text="Select the folder where Destiny 2 should be downloaded and installed:" FontSize="12" Foreground="#64748B" Margin="0,0,0,10"/>

                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox Name="TxtDownloadDir" Grid.Column="0" Background="#12151B" Foreground="#F8FAFC" BorderBrush="#384252" BorderThickness="1" FontSize="13" Padding="10,8" VerticalContentAlignment="Center" Margin="0,0,8,0"/>
                                    <Button Name="BtnBrowseDownloadDir" Grid.Column="1" Style="{StaticResource StandardBtn}" Content="Browse..."/>
                                </Grid>

                                <!-- Disk space indicator -->
                                <Border Name="DownloadSpaceBorder" Background="#1B2822" BorderBrush="#22C55E" BorderThickness="1" CornerRadius="5" Padding="10,6" HorizontalAlignment="Left">
                                    <TextBlock Name="DownloadSpaceText" Text="Calculating disk space..." FontSize="12" Foreground="#86EFAC"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- AUTHENTICATION SETTINGS -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="STEAM AUTHENTICATION" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,8"/>

                                <RadioButton Name="RadioAuthQr" Content="Steam Mobile App QR Code (Recommended)" IsChecked="True" Foreground="#F1F5F9" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,3"/>
                                <TextBlock Text="Fast &amp; secure: No username or password required. Scan the QR code in the console using your Steam Mobile App." FontSize="11.5" Foreground="#64748B" Margin="22,0,0,12"/>

                                <RadioButton Name="RadioAuthUser" Content="Steam Account Username &amp; Password" Foreground="#F1F5F9" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,3"/>
                                <TextBlock Text="Enter your Steam login username. You will be prompted for your password and Steam Guard code." FontSize="11.5" Foreground="#64748B" Margin="22,0,0,8"/>

                                <StackPanel Name="PanelSteamUser" Visibility="Collapsed" Margin="22,4,0,0">
                                    <TextBlock Text="Steam Username (account login name, not profile display name):" FontSize="12" Foreground="#94A3B8" Margin="0,0,0,4"/>
                                    <TextBox Name="TxtSteamUsername" MaxWidth="320" HorizontalAlignment="Left" Background="#12151B" Foreground="#F8FAFC" BorderBrush="#384252" BorderThickness="1" FontSize="13" Padding="8,6"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- DOWNLOAD OPTIONS & ACTION -->
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18">
                            <StackPanel>
                                <Grid Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>

                                    <StackPanel Grid.Column="0">
                                        <CheckBox Name="ChkDownloadConsole" Content="Launch download in interactive terminal window (Recommended)" IsChecked="True" Foreground="#CBD5E1" FontSize="12.5" Margin="0,0,0,6"/>
                                        <TextBlock Text="Opens a command prompt displaying the ANSI QR code for mobile scanning and live progress." FontSize="11" Foreground="#64748B"/>
                                    </StackPanel>

                                    <Button Name="BtnStartDownload" Grid.Column="1" Style="{StaticResource PrimaryBtn}" Content="&#x2B07; Download Destiny 2" MinWidth="200" Height="42" VerticalAlignment="Center"/>
                                </Grid>

                                <!-- Download progress status -->
                                <StackPanel Name="DownloadProgressContainer" Visibility="Collapsed" Margin="0,8,0,0">
                                    <TextBlock Name="TxtDownloadProgressStatus" Text="Starting download process..." FontSize="12" Foreground="#E5A93C" FontWeight="SemiBold" Margin="0,0,0,6"/>
                                    <ProgressBar Name="DownloadProgressBar" Height="6" Background="#262D38" Foreground="#E5A93C" BorderThickness="0" IsIndeterminate="True"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 3: BACKUPS & ROLLBACK -->
            <TabItem Name="TabBackups" Header="Backups &amp; Rollback">
                <Grid Margin="4,10,4,10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="16" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0">
                                <TextBlock Text="RELEASE BACKUPS &amp; RESTORE POINTS" FontSize="12" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock Text="Select a backup point below to restore previous Dawn files and display preferences. Files modified since installation are safely saved to that backup's after-restore folder." FontSize="11.5" Foreground="#64748B" Margin="0,3,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                            <Button Name="BtnRefreshBackups" Grid.Column="1" Style="{StaticResource StandardBtn}" Content="&#x21BA; Refresh" VerticalAlignment="Center" Margin="10,0,0,0"/>
                        </Grid>
                    </Border>

                    <!-- Backups List -->
                    <Border Grid.Row="1" Background="#161920" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Margin="0,0,0,12">
                        <ListBox Name="ListBackups" Background="Transparent" BorderThickness="0" Foreground="#F1F5F9" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                            <ListBox.ItemTemplate>
                                <DataTemplate>
                                    <Border Background="#1F2530" BorderBrush="#2D3545" BorderThickness="1" CornerRadius="6" Padding="14,10" Margin="4,3">
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="{Binding Timestamp}" FontWeight="Bold" FontSize="13" Foreground="#F8FAFC" Margin="0,0,10,0"/>
                                                    <Border Background="#2B3444" CornerRadius="3" Padding="6,2" VerticalAlignment="Center">
                                                        <TextBlock Text="{Binding Release}" FontSize="11" Foreground="#E5A93C"/>
                                                    </Border>
                                                </StackPanel>
                                                <TextBlock Text="{Binding FolderName}" FontSize="11" Foreground="#64748B" Margin="0,4,0,0"/>
                                            </StackPanel>
                                            <Border Grid.Column="1" Background="{Binding StateBg}" CornerRadius="4" Padding="8,4" VerticalAlignment="Center">
                                                <TextBlock Text="{Binding StateText}" FontSize="11" FontWeight="Bold" Foreground="{Binding StateFg}"/>
                                            </Border>
                                        </Grid>
                                    </Border>
                                </DataTemplate>
                            </ListBox.ItemTemplate>
                        </ListBox>
                    </Border>

                    <!-- Rollback Action Bar -->
                    <Border Grid.Row="2" Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="16">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                <CheckBox Name="ChkRestoreWhatIf" Content="Dry Run Mode (-WhatIf: test rollback without touching files)" Foreground="#CBD5E1" FontSize="12.5" Margin="0,0,0,4"/>
                                <TextBlock Text="Restores the selected backup. Dawn files displaced by rollback are kept in after-restore." FontSize="11" Foreground="#64748B"/>
                            </StackPanel>
                            <Button Name="BtnRestore" Grid.Column="1" Style="{StaticResource StandardBtn}" Content="&#x21A9; Restore Selected Backup" MinWidth="190" Height="38" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 4: CONSOLE / LOGS -->
            <TabItem Name="TabConsole" Header="Console Logs">
                <Grid Margin="4,10,4,10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Log Toolbar -->
                    <Border Grid.Row="0" Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1,1,1,0" CornerRadius="8,8,0,0" Padding="12,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="LIVE INSTALLER STREAM" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" VerticalAlignment="Center"/>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Name="BtnCopyLog" Style="{StaticResource StandardBtn}" Content="Copy Log" Padding="10,4" Margin="0,0,8,0"/>
                                <Button Name="BtnClearLog" Style="{StaticResource StandardBtn}" Content="Clear Console" Padding="10,4"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Terminal Box -->
                    <Border Grid.Row="1" Background="#0C0E12" BorderBrush="#29313E" BorderThickness="1,0,1,1" CornerRadius="0,0,8,8">
                        <TextBox Name="TxtConsole" Background="Transparent" Foreground="#E2E8F0" FontFamily="Consolas, Cascadia Code, Courier New" FontSize="12" BorderThickness="0" Padding="14" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 5: ABOUT & GUIDE -->
            <TabItem Header="Guide &amp; Info">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="10,14,10,14">
                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="STEAM DEPOT DOWNLOADER GUIDE" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                                <TextBlock Text="&#x2022; Destiny 2 Build 86657 is downloaded directly from Steam's content delivery network using DepotDownloader." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; Requires a Steam account with Destiny 2 in its library (Destiny 2 is free on Steam)." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; The downloader fetches two depots: 1085661 (Content, Manifest 7180122903232116872) and 1085662 (Binaries, Manifest 2210332166360342287)." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; Downloads are resumeable: If your connection is interrupted, running the download again picks up from the last chunk." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="ABOUT DAWN INSTALLATION" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                                <TextBlock Text="&#x2022; Every installation starts a fresh profile using release defaults. Existing progress, settings, identity, event choices, and custom scripts are not carried into the new install." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; The game will automatically generate a new player database from release defaults on first launch." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; Old Sunrise and Restoration folders are completely untouched and ignored." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <TextBlock Text="&#x2022; Previous Dawn folders and DLLs are automatically backed up in .dawn/release-backups." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18" Margin="0,0,0,14">
                            <StackPanel>
                                <TextBlock Text="DISPLAY PREFERENCES" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                                <TextBlock Text="The installer automatically sets Windowed Fullscreen as the launch default for the Windows user running it. Your resolution, graphics quality, and key bindings are preserved. You can change video modes at any time in the in-game Video settings." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#1A1F27" BorderBrush="#29313E" BorderThickness="1" CornerRadius="8" Padding="18">
                            <StackPanel>
                                <TextBlock Text="ROLLBACK &amp; SAFETY" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                                <TextBlock Text="A persistent transactional journal tracks all replaced targets. If an installation is interrupted or cancelled, the journal ensures reliable recovery. Displaced files from a rollback are archived in the backup's after-restore directory so progress is never permanently lost." FontSize="12.5" Foreground="#CBD5E1" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- STATUS BAR FOOTER -->
        <Border Grid.Row="2" Background="#161920" BorderBrush="#262D38" BorderThickness="0,1,0,0" Padding="16,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Left: Operation status -->
                <TextBlock Name="FooterStatusText" Grid.Column="0" Text="Ready" FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>

                <!-- Right: Game process status badge -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Name="ProcStatusDot" Width="8" Height="8" Fill="#22C55E" Margin="0,0,6,0"/>
                    <TextBlock Name="ProcStatusText" Text="Destiny 2 is Closed" FontSize="11.5" Foreground="#94A3B8"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

# --- Instantiate Window & Controls ---
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Catch unhandled dispatcher exceptions to prevent window termination
$window.Dispatcher.add_UnhandledException({
    param($sender, $e)
    try {
        $txtConsole.AppendText("[ERROR] Unhandled UI error: $($e.Exception.Message)`r`n")
    } catch {}
    $e.Handled = $true
})

# Control References - General
$headerReleaseBadge       = $window.FindName('HeaderReleaseBadge')
$btnLaunchGame            = $window.FindName('BtnLaunchGame')
$mainTabs                 = $window.FindName('MainTabs')
$tabInstall               = $window.FindName('TabInstall')
$tabDownload              = $window.FindName('TabDownload')
$tabBackups               = $window.FindName('TabBackups')
$tabConsole               = $window.FindName('TabConsole')
$footerStatusText         = $window.FindName('FooterStatusText')
$procStatusDot            = $window.FindName('ProcStatusDot')
$procStatusText           = $window.FindName('ProcStatusText')

# Control References - Install Tab
$alertInterruptedBox      = $window.FindName('AlertInterruptedBox')
$alertInterruptedText     = $window.FindName('AlertInterruptedText')
$btnRecoverInterrupted    = $window.FindName('BtnRecoverInterrupted')
$bannerNeedDownload       = $window.FindName('BannerNeedDownload')
$btnGoToDownloadTab       = $window.FindName('BtnGoToDownloadTab')
$txtGameRoot              = $window.FindName('TxtGameRoot')
$btnBrowse                = $window.FindName('BtnBrowse')
$btnAutoDetect            = $window.FindName('BtnAutoDetect')
$gameStatusBorder         = $window.FindName('GameStatusBorder')
$gameStatusIcon           = $window.FindName('GameStatusIcon')
$gameStatusText           = $window.FindName('GameStatusText')
$lblReleaseVer            = $window.FindName('LblReleaseVer')
$lblTargetBuild           = $window.FindName('LblTargetBuild')
$lblPayloadCount          = $window.FindName('LblPayloadCount')
$chkWhatIf                = $window.FindName('ChkWhatIf')
$btnInstall               = $window.FindName('BtnInstall')
$progressContainer        = $window.FindName('ProgressContainer')
$txtProgressStatus        = $window.FindName('TxtProgressStatus')
$installProgressBar       = $window.FindName('InstallProgressBar')

# Control References - Download Tab
$toolStatusPill           = $window.FindName('ToolStatusPill')
$toolStatusText           = $window.FindName('ToolStatusText')
$txtDownloadDir           = $window.FindName('TxtDownloadDir')
$btnBrowseDownloadDir     = $window.FindName('BtnBrowseDownloadDir')
$downloadSpaceBorder      = $window.FindName('DownloadSpaceBorder')
$downloadSpaceText        = $window.FindName('DownloadSpaceText')
$radioAuthQr              = $window.FindName('RadioAuthQr')
$radioAuthUser            = $window.FindName('RadioAuthUser')
$panelSteamUser           = $window.FindName('PanelSteamUser')
$txtSteamUsername         = $window.FindName('TxtSteamUsername')
$chkDownloadConsole       = $window.FindName('ChkDownloadConsole')
$btnStartDownload         = $window.FindName('BtnStartDownload')
$downloadProgressContainer= $window.FindName('DownloadProgressContainer')
$txtDownloadProgressStatus= $window.FindName('TxtDownloadProgressStatus')
$downloadProgressBar     = $window.FindName('DownloadProgressBar')

# Control References - Backups Tab
$btnRefreshBackups        = $window.FindName('BtnRefreshBackups')
$listBackups              = $window.FindName('ListBackups')
$chkRestoreWhatIf         = $window.FindName('ChkRestoreWhatIf')
$btnRestore               = $window.FindName('BtnRestore')

# Control References - Console Tab
$btnCopyLog               = $window.FindName('BtnCopyLog')
$btnClearLog              = $window.FindName('BtnClearLog')
$txtConsole               = $window.FindName('TxtConsole')

# State variables
$script:CurrentManifest        = $null
$script:IsGameValid            = $false
$script:IsGameRunning          = $false
$script:InterruptedBackupPath  = $null
$script:IsRunningInstaller     = $false
$script:IsRunningDownload      = $false

# --- Helper Functions ---
function Load-ReleaseManifest {
    try {
        if (-not (Test-Path -LiteralPath $script:ReleaseManifestPath)) {
            $lblReleaseVer.Text = "Missing release.json"
            $headerReleaseBadge.Text = "Unknown"
            return
        }
        $manifest = Get-Content -LiteralPath $script:ReleaseManifestPath -Raw | ConvertFrom-Json
        $script:CurrentManifest = $manifest
        $headerReleaseBadge.Text = "v$($manifest.release)"
        $lblReleaseVer.Text = "$($manifest.release)"
        $lblTargetBuild.Text = "$($manifest.gameBuild) (Destiny 2)"
        $lblPayloadCount.Text = "$(@($manifest.files).Count) verified payload files"
    } catch {
        $lblReleaseVer.Text = "Error loading manifest: $($_.Exception.Message)"
    }
}

function Set-StatusText([string] $Text) {
    $footerStatusText.Text = $Text
}

function Log-Message([string] $Message) {
    $txtConsole.AppendText($Message + "`r`n")
    $txtConsole.ScrollToEnd()
}

function Format-BackupTimestamp([string] $Name) {
    if ($Name -match '^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})') {
        return "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
    }
    return $Name
}

function Update-DownloadDiskSpace {
    $dir = $txtDownloadDir.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $downloadSpaceBorder.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($dir)
        $root = [System.IO.Path]::GetPathRoot($fullPath)
        if (-not $root) { return }
        $drive = New-Object System.IO.DriveInfo($root)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)

        $downloadSpaceBorder.Visibility = [System.Windows.Visibility]::Visible
        if ($freeGB -ge 100) {
            $downloadSpaceBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 27, 40, 34))
            $downloadSpaceBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 34, 197, 94))
            $downloadSpaceText.Text = "Drive $root  $freeGB GB available (100 GB required) - Sufficient Space"
            $downloadSpaceText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 134, 239, 172))
        } elseif ($freeGB -ge 80) {
            $downloadSpaceBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 43, 20))
            $downloadSpaceBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 245, 158, 11))
            $downloadSpaceText.Text = "Drive $root  $freeGB GB available (100 GB required) - Storage is tight"
            $downloadSpaceText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 211, 77))
        } else {
            $downloadSpaceBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 28, 28))
            $downloadSpaceBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 220, 38, 38))
            $downloadSpaceText.Text = "Drive $root  $freeGB GB available (100 GB required) - Insufficient free space!"
            $downloadSpaceText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
        }
    } catch {
        $downloadSpaceBorder.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

function Update-ToolStatus {
    $exe = Find-DepotDownloaderExe
    if ($exe) {
        $toolStatusPill.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 20, 83, 45))
        $toolStatusText.Text = "[OK] DepotDownloader Ready"
        $toolStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 134, 239, 172))
    } else {
        $toolStatusPill.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 127, 29, 29))
        $toolStatusText.Text = "[!] DepotDownloader Missing"
        $toolStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
    }
}

function Update-BackupsList {
    $gameRoot = $txtGameRoot.Text.Trim()
    $script:InterruptedBackupPath = $null
    $alertInterruptedBox.Visibility = [System.Windows.Visibility]::Collapsed

    if (-not $gameRoot -or -not (Test-Path -LiteralPath $gameRoot)) {
        $listBackups.ItemsSource = @()
        $btnRestore.IsEnabled = $false
        return
    }

    $backupRoot = Join-Path $gameRoot '.dawn\release-backups'
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        $listBackups.ItemsSource = @()
        $btnRestore.IsEnabled = $false
        return
    }

    $items = New-Object System.Collections.Generic.List[PSCustomObject]
    $dirs = Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object Name -Descending
    foreach ($dir in $dirs) {
        $journalPath = Join-Path $dir.FullName 'journal.json'
        if (Test-Path -LiteralPath $journalPath) {
            try {
                $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
                $state = if ($journal.PSObject.Properties['state']) { $journal.state } else { 'unknown' }
                $rel = if ($journal.PSObject.Properties['release'] -and $journal.release) { "v$($journal.release)" } else { "Release" }

                $stateBg = "#1E293B"
                $stateFg = "#94A3B8"
                $stateText = $state

                if ($state -eq 'complete') {
                    $stateBg = "#14532D"
                    $stateFg = "#86EFAC"
                    $stateText = "Installed"
                } elseif ($state -eq 'restored') {
                    $stateBg = "#1F2937"
                    $stateFg = "#9CA3AF"
                    $stateText = "Rolled Back"
                } else {
                    $stateBg = "#7F1D1D"
                    $stateFg = "#FCA5A5"
                    $stateText = "Interrupted ($state)"
                    if (-not $script:InterruptedBackupPath) {
                        $script:InterruptedBackupPath = $dir.FullName
                    }
                }

                $items.Add([PSCustomObject]@{
                    FolderName = $dir.Name
                    Timestamp  = Format-BackupTimestamp $dir.Name
                    Release    = $rel
                    Path       = $dir.FullName
                    State      = $state
                    StateText  = $stateText
                    StateBg    = $stateBg
                    StateFg    = $stateFg
                })
            } catch {}
        }
    }

    $listBackups.ItemsSource = $items
    $btnRestore.IsEnabled = ($items.Count -gt 0 -and -not $script:IsGameRunning -and -not $script:IsRunningInstaller -and -not $script:IsRunningDownload)

    if ($script:InterruptedBackupPath) {
        $alertInterruptedBox.Visibility = [System.Windows.Visibility]::Visible
        $alertInterruptedText.Text = "An interrupted operation was detected in $($script:InterruptedBackupPath). Run recovery rollback before installing."
    }
}

function Update-GameValidation {
    $path = $txtGameRoot.Text.Trim()
    $script:IsGameValid = $false

    if ([string]::IsNullOrWhiteSpace($path)) {
        $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 30, 41, 59))
        $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 71, 85, 105))
        $gameStatusIcon.Text = "-"
        $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 148, 163, 184))
        $gameStatusText.Text = "Please enter or browse to your Destiny 2 folder"
        $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 148, 163, 184))
        $btnInstall.IsEnabled = $false
        $btnLaunchGame.IsEnabled = $false
        $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Visible
        Update-BackupsList
        return
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 28, 28))
        $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 220, 38, 38))
        $gameStatusIcon.Text = [char]0x2715
        $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
        $gameStatusText.Text = "Folder does not exist"
        $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
        $btnInstall.IsEnabled = $false
        $btnLaunchGame.IsEnabled = $false
        $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Visible
        Update-BackupsList
        return
    }

    $exePath = Join-Path $path 'destiny2.exe'
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 28, 28))
        $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 220, 38, 38))
        $gameStatusIcon.Text = [char]0x2715
        $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
        $gameStatusText.Text = "destiny2.exe not found in this directory"
        $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
        $btnInstall.IsEnabled = $false
        $btnLaunchGame.IsEnabled = $false
        $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Visible
        Update-BackupsList
        return
    }

    try {
        $fileVer = (Get-Item -LiteralPath $exePath).VersionInfo.FileVersion
        if ($fileVer -ne $script:ExpectedFileVersion) {
            $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 28, 28))
            $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 220, 38, 38))
            $gameStatusIcon.Text = [char]0x26A0
            $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
            $gameStatusText.Text = "Unsupported Destiny 2 version: $fileVer (Expected $script:ExpectedFileVersion)"
            $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
            $btnInstall.IsEnabled = $false
            $btnLaunchGame.IsEnabled = $false
            $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Visible
            Update-BackupsList
            return
        }
    } catch {
        $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 59, 28, 28))
        $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 220, 38, 38))
        $gameStatusIcon.Text = [char]0x26A0
        $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
        $gameStatusText.Text = "Could not read version info from destiny2.exe"
        $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
        $btnInstall.IsEnabled = $false
        $btnLaunchGame.IsEnabled = $false
        $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Visible
        Update-BackupsList
        return
    }

    # Everything valid!
    $script:IsGameValid = $true
    $bannerNeedDownload.Visibility = [System.Windows.Visibility]::Collapsed
    $gameStatusBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 27, 40, 34))
    $gameStatusBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 34, 197, 94))
    $gameStatusIcon.Text = [char]0x2713
    $gameStatusIcon.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 34, 197, 94))
    $gameStatusText.Text = "Verified Destiny 2 build 86657.20.08.23.1800.d2_rc"
    $gameStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 134, 239, 172))

    Update-BackupsList

    $canInstall = ($script:IsGameValid -and -not $script:IsGameRunning -and -not $script:InterruptedBackupPath -and -not $script:IsRunningInstaller -and -not $script:IsRunningDownload)
    $btnInstall.IsEnabled = $canInstall
    $btnLaunchGame.IsEnabled = ($script:IsGameValid -and -not $script:IsGameRunning -and -not $script:IsRunningInstaller -and -not $script:IsRunningDownload)

    $steamUser = if ($txtSteamUsername -and $txtSteamUsername.Text) { $txtSteamUsername.Text.Trim() } else { '' }
    $dlDir = if ($txtDownloadDir -and $txtDownloadDir.Text) { $txtDownloadDir.Text.Trim() } else { '' }
    Save-UserSettings $path $dlDir $steamUser
}

# --- Execution Engine for Installer ---
function Run-InstallerScript([string[]] $ScriptArguments, [string] $OperationTitle) {
    if ($script:IsRunningInstaller -or $script:IsRunningDownload) { return }

    $script:IsRunningInstaller = $true
    $btnInstall.IsEnabled = $false
    $btnRestore.IsEnabled = $false
    $btnRecoverInterrupted.IsEnabled = $false
    $btnBrowse.IsEnabled = $false
    $btnAutoDetect.IsEnabled = $false
    $btnLaunchGame.IsEnabled = $false
    $btnStartDownload.IsEnabled = $false
    $txtGameRoot.IsEnabled = $false

    $progressContainer.Visibility = [System.Windows.Visibility]::Visible
    $txtProgressStatus.Text = "$OperationTitle in progress..."
    Set-StatusText "$OperationTitle..."

    $mainTabs.SelectedItem = $tabConsole

    Log-Message "=========================================================="
    Log-Message "[$(Get-Date -Format 'HH:mm:ss')] Starting $OperationTitle"
    Log-Message "Arguments: $($ScriptArguments -join ' ')"
    Log-Message "=========================================================="

    $tempLog = [System.IO.Path]::GetTempFileName()
    $fullArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$script:InstallerScriptPath`"") + $ScriptArguments
    $cmdArg = "/c powershell.exe $($fullArgs -join ' ') > `"$tempLog`" 2>&1"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = $cmdArg
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Log-Message "[ERROR] Failed to start installer process: $($_.Exception.Message)"
        $script:IsRunningInstaller = $false
        $progressContainer.Visibility = [System.Windows.Visibility]::Collapsed
        Update-GameValidation
        return
    }

    $stream = [System.IO.File]::Open($tempLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(60)

    $timer.add_Tick({
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($null -ne $line) {
                    Log-Message $line
                    if ($line -like 'Release:*') {
                        $txtProgressStatus.Text = "Validating release package..."
                    } elseif ($line -like 'Game:*') {
                        $txtProgressStatus.Text = "Checking target game folder..."
                    } elseif ($line -like 'Save:*') {
                        $txtProgressStatus.Text = "Preparing profile..."
                    } elseif ($line -like 'Display:*') {
                        $txtProgressStatus.Text = "Configuring windowed fullscreen..."
                    } elseif ($line -like 'What if:*') {
                        $txtProgressStatus.Text = "Simulating operations (WhatIf)..."
                    } elseif ($line -like 'Installed Dawn*') {
                        $txtProgressStatus.Text = "Installation finished!"
                    } elseif ($line -like 'Restored.*') {
                        $txtProgressStatus.Text = "Restoration finished!"
                    }
                }
            }

            if ($proc.HasExited) {
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()
                    if ($null -ne $line) { Log-Message $line }
                }

                $reader.Dispose()
                $stream.Dispose()
                Remove-Item -LiteralPath $tempLog -Force -ErrorAction SilentlyContinue
                $timer.Stop()

                $exitCode = $proc.ExitCode
                $proc.Dispose()

                $script:IsRunningInstaller = $false
                $progressContainer.Visibility = [System.Windows.Visibility]::Collapsed
                $txtGameRoot.IsEnabled = $true
                $btnBrowse.IsEnabled = $true
                $btnAutoDetect.IsEnabled = $true
                $btnStartDownload.IsEnabled = $true

                if ($exitCode -eq 0) {
                    Log-Message "=========================================================="
                    Log-Message "[$(Get-Date -Format 'HH:mm:ss')] $OperationTitle completed successfully (Exit Code 0)."
                    Log-Message "=========================================================="
                    Set-StatusText "$OperationTitle completed successfully."
                    [System.Windows.MessageBox]::Show("$OperationTitle completed successfully!", "Dawn Installer", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                } else {
                    Log-Message "=========================================================="
                    Log-Message "[$(Get-Date -Format 'HH:mm:ss')] $OperationTitle encountered errors (Exit Code $exitCode)."
                    Log-Message "=========================================================="
                    Set-StatusText "$OperationTitle failed. Check logs for details."
                    [System.Windows.MessageBox]::Show("$OperationTitle did not complete. Please inspect the Console Logs tab for details.", "Dawn Installer Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
                }

                Update-GameValidation
            }
        } catch {
            Log-Message "[ERROR in watcher]: $($_.Exception.Message)"
        }
    })

    $timer.Start()
}

# --- Execution Engine for Steam Depot Downloader ---
function Start-SteamDownloadProcess {
    if ($script:IsRunningInstaller -or $script:IsRunningDownload) { return }

    $targetDir = $txtDownloadDir.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($targetDir)) {
        [System.Windows.MessageBox]::Show("Please specify a target installation directory for Destiny 2.", "Directory Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $isQr = ($radioAuthQr.IsChecked -eq $true)
    $username = $txtSteamUsername.Text.Trim()
    if (-not $isQr -and [string]::IsNullOrWhiteSpace($username)) {
        [System.Windows.MessageBox]::Show("Please enter your Steam username, or switch to Steam Mobile App QR Code authentication.", "Steam Username Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $script:IsRunningDownload = $true
    $btnStartDownload.IsEnabled = $false
    $btnInstall.IsEnabled = $false
    $btnRestore.IsEnabled = $false
    $downloadProgressContainer.Visibility = [System.Windows.Visibility]::Visible
    $txtDownloadProgressStatus.Text = "Downloading Destiny 2 build 86657..."
    Set-StatusText "Steam Depot Downloader running..."

    Save-UserSettings $txtGameRoot.Text.Trim() $targetDir $username

    $argsList = New-Object System.Collections.Generic.List[string]
    $argsList.Add("-Destination")
    $argsList.Add("`"$targetDir`"")

    if ($isQr) {
        $argsList.Add("-UseQrCode")
    } else {
        $argsList.Add("-SteamUsername")
        $argsList.Add("`"$username`"")
    }

    if ($chkDownloadConsole.IsChecked) {
        $scriptArgString = ($argsList -join ' ')
        $cmdLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script:DownloadScriptPath`" $scriptArgString"

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = "/c $cmdLine & pause"
        $psi.UseShellExecute = $true

        try {
            $dlProc = [System.Diagnostics.Process]::Start($psi)
        } catch {
            [System.Windows.MessageBox]::Show("Failed to launch downloader window: $($_.Exception.Message)", "Download Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            $script:IsRunningDownload = $false
            $btnStartDownload.IsEnabled = $true
            $downloadProgressContainer.Visibility = [System.Windows.Visibility]::Collapsed
            return
        }

        $watchTimer = New-Object System.Windows.Threading.DispatcherTimer
        $watchTimer.Interval = [TimeSpan]::FromSeconds(1)
        $watchTimer.add_Tick({
            if ($dlProc.HasExited) {
                $watchTimer.Stop()
                $dlProc.Dispose()

                $script:IsRunningDownload = $false
                $btnStartDownload.IsEnabled = $true
                $downloadProgressContainer.Visibility = [System.Windows.Visibility]::Collapsed
                Set-StatusText "Download finished."

                $exe = Join-Path $targetDir 'destiny2.exe'
                if (Test-Path -LiteralPath $exe -PathType Leaf) {
                    try {
                        $ver = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
                        if ($ver -eq $script:ExpectedFileVersion) {
                            $txtGameRoot.Text = $targetDir
                            $mainTabs.SelectedItem = $tabInstall
                            Update-GameValidation
                            [System.Windows.MessageBox]::Show("Destiny 2 build $ver has been successfully downloaded and verified!`nYou can now click 'Install Dawn' to complete the installation.", "Download Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                            return
                        }
                    } catch {}
                }
                Update-GameValidation
            }
        })
        $watchTimer.Start()

    } else {
        $mainTabs.SelectedItem = $tabConsole
        Log-Message "=========================================================="
        Log-Message "[$(Get-Date -Format 'HH:mm:ss')] Starting Steam Depot Downloader"
        Log-Message "Destination: $targetDir"
        Log-Message "=========================================================="

        $tempLog = [System.IO.Path]::GetTempFileName()
        $fullArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$script:DownloadScriptPath`"") + $argsList
        $cmdArg = "/c powershell.exe $($fullArgs -join ' ') > `"$tempLog`" 2>&1"

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = $cmdArg
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false

        try {
            $dlProc = [System.Diagnostics.Process]::Start($psi)
        } catch {
            Log-Message "[ERROR] Failed to start downloader: $($_.Exception.Message)"
            $script:IsRunningDownload = $false
            $btnStartDownload.IsEnabled = $true
            $downloadProgressContainer.Visibility = [System.Windows.Visibility]::Collapsed
            return
        }

        $stream = [System.IO.File]::Open($tempLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $dlReader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

        $dlTimer = New-Object System.Windows.Threading.DispatcherTimer
        $dlTimer.Interval = [TimeSpan]::FromMilliseconds(80)

        $dlTimer.add_Tick({
            try {
                while (-not $dlReader.EndOfStream) {
                    $line = $dlReader.ReadLine()
                    if ($null -ne $line) {
                        Log-Message $line
                        if ($line -like '*Step 1/2*') {
                            $txtDownloadProgressStatus.Text = "Downloading Content Depot 1085661..."
                        } elseif ($line -like '*Step 2/2*') {
                            $txtDownloadProgressStatus.Text = "Downloading Binaries Depot 1085662..."
                        } elseif ($line -like '*VERIFIED*') {
                            $txtDownloadProgressStatus.Text = "Download verified!"
                        }
                    }
                }

                if ($dlProc.HasExited) {
                    while (-not $dlReader.EndOfStream) {
                        $line = $dlReader.ReadLine()
                        if ($null -ne $line) { Log-Message $line }
                    }

                    $dlReader.Dispose()
                    $stream.Dispose()
                    Remove-Item -LiteralPath $tempLog -Force -ErrorAction SilentlyContinue
                    $dlTimer.Stop()

                    $exitCode = $dlProc.ExitCode
                    $dlProc.Dispose()

                    $script:IsRunningDownload = $false
                    $btnStartDownload.IsEnabled = $true
                    $downloadProgressContainer.Visibility = [System.Windows.Visibility]::Collapsed

                    if ($exitCode -eq 0) {
                        Log-Message "[$(Get-Date -Format 'HH:mm:ss')] Download finished successfully."
                        Set-StatusText "Steam download completed."

                        $exe = Join-Path $targetDir 'destiny2.exe'
                        if (Test-Path -LiteralPath $exe -PathType Leaf) {
                            $txtGameRoot.Text = $targetDir
                            $mainTabs.SelectedItem = $tabInstall
                            Update-GameValidation
                            [System.Windows.MessageBox]::Show("Destiny 2 build has been downloaded and verified!`nYou can now click 'Install Dawn'.", "Download Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                        }
                    } else {
                        Log-Message "[$(Get-Date -Format 'HH:mm:ss')] Download exited with code $exitCode."
                        Set-StatusText "Download encountered errors."
                        [System.Windows.MessageBox]::Show("Download did not complete successfully (Exit Code $exitCode). Check Console Logs for details.", "Download Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
                    }

                    Update-GameValidation
                }
            } catch {
                Log-Message "[ERROR in downloader watcher]: $($_.Exception.Message)"
            }
        })

        $dlTimer.Start()
    }
}

# --- Event Wiring ---

# Game folder text changed
$txtGameRoot.add_TextChanged({
    Update-GameValidation
})

# Browse Button in Install Tab
$btnBrowse.add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select Destiny 2 (destiny2.exe) in your game directory"
    $dlg.Filter = "Destiny 2 (destiny2.exe)|destiny2.exe|All Executables (*.exe)|*.exe|All Files (*.*)|*.*"
    $dlg.FileName = "destiny2.exe"

    if ($txtGameRoot.Text -and (Test-Path -LiteralPath $txtGameRoot.Text)) {
        $dlg.InitialDirectory = $txtGameRoot.Text
    }

    if ($dlg.ShowDialog() -eq $true) {
        $folder = [System.IO.Path]::GetDirectoryName($dlg.FileName)
        $txtGameRoot.Text = $folder
    }
})

# Auto-Detect Button
$btnAutoDetect.add_Click({
    Set-StatusText "Searching for Destiny 2 installation..."
    $detected = Find-DestinyGameDirectory
    if ($detected) {
        $txtGameRoot.Text = $detected
        Set-StatusText "Found valid Destiny 2 directory: $detected"
    } else {
        Set-StatusText "Could not automatically locate a compatible Destiny 2 installation."
        [System.Windows.MessageBox]::Show("Could not find a Destiny 2 directory matching build $script:ExpectedFileVersion.`nYou can download it via the 'Download Game Build' tab.", "Auto-Detect", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

# Callout banner button -> Go to Download Tab
$btnGoToDownloadTab.add_Click({
    $mainTabs.SelectedItem = $tabDownload
})

# Install Button
$btnInstall.add_Click({
    if (-not $script:IsGameValid) { return }

    $gameRoot = $txtGameRoot.Text.Trim()
    $argsList = @("-GameRoot", "`"$gameRoot`"")
    if ($chkWhatIf.IsChecked) {
        $argsList += "-WhatIf"
    }

    $opName = if ($chkWhatIf.IsChecked) { "Simulation (WhatIf)" } else { "Installation" }
    Run-InstallerScript $argsList $opName
})

# Download Tab: Target Directory Changed
$txtDownloadDir.add_TextChanged({
    Update-DownloadDiskSpace
})

# Download Tab: Browse Directory Button
$btnBrowseDownloadDir.add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select or create destination directory for Destiny 2"
    $dlg.Filter = "Destiny 2 Folder Placeholder|destiny2.exe|All Files (*.*)|*.*"
    $dlg.FileName = "Select This Folder"
    $dlg.CheckFileExists = $false

    if ($txtDownloadDir.Text -and (Test-Path -LiteralPath $txtDownloadDir.Text)) {
        $dlg.InitialDirectory = $txtDownloadDir.Text
    }

    if ($dlg.ShowDialog() -eq $true) {
        $selectedDir = [System.IO.Path]::GetDirectoryName($dlg.FileName)
        $txtDownloadDir.Text = $selectedDir
    }
})

# Download Tab: Auth Mode Radio Toggled
$radioAuthQr.add_Checked({
    $panelSteamUser.Visibility = [System.Windows.Visibility]::Collapsed
})
$radioAuthUser.add_Checked({
    $panelSteamUser.Visibility = [System.Windows.Visibility]::Visible
})

# Download Tab: Start Download Button
$btnStartDownload.add_Click({
    Start-SteamDownloadProcess
})

# Refresh Backups Button
$btnRefreshBackups.add_Click({
    Update-BackupsList
    Set-StatusText "Backups refreshed."
})

# Restore Selected Backup Button
$btnRestore.add_Click({
    $selected = $listBackups.SelectedItem
    $gameRoot = $txtGameRoot.Text.Trim()
    $backupPath = $null

    if ($selected) {
        $backupPath = $selected.Path
    }

    $msg = if ($backupPath) {
        "Are you sure you want to restore the selected backup:`n$($selected.Timestamp) ($($selected.Release))?`n`nCurrent Dawn files will be preserved in after-restore."
    } else {
        "Are you sure you want to restore the latest backup?`n`nCurrent Dawn files will be preserved in after-restore."
    }

    $res = [System.Windows.MessageBox]::Show($msg, "Confirm Rollback / Restore", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $argsList = @("-GameRoot", "`"$gameRoot`"", "-Restore")
    if ($backupPath) {
        $argsList += @("-BackupPath", "`"$backupPath`"")
    }
    if ($chkRestoreWhatIf.IsChecked) {
        $argsList += "-WhatIf"
    }

    $opName = if ($chkRestoreWhatIf.IsChecked) { "Rollback Simulation (WhatIf)" } else { "Rollback" }
    Run-InstallerScript $argsList $opName
})

# Recover Interrupted Installation Button
$btnRecoverInterrupted.add_Click({
    if (-not $script:InterruptedBackupPath) { return }

    $gameRoot = $txtGameRoot.Text.Trim()
    $res = [System.Windows.MessageBox]::Show("Recover and rollback the interrupted installation at:`n$($script:InterruptedBackupPath)?", "Recover Interrupted Install", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $argsList = @("-GameRoot", "`"$gameRoot`"", "-Restore", "-BackupPath", "`"$($script:InterruptedBackupPath)`"")
    Run-InstallerScript $argsList "Recovery Rollback"
})

# Launch Game Button
$btnLaunchGame.add_Click({
    $gameRoot = $txtGameRoot.Text.Trim()
    if (-not $gameRoot -or -not (Test-Path -LiteralPath (Join-Path $gameRoot 'destiny2.exe'))) {
        [System.Windows.MessageBox]::Show("Invalid game folder. destiny2.exe was not found.", "Launch Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    if ($script:IsGameRunning) {
        [System.Windows.MessageBox]::Show("Destiny 2 is already running!", "Launch Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }

    try {
        Start-Process -FilePath (Join-Path $gameRoot 'destiny2.exe') -WorkingDirectory $gameRoot
        Set-StatusText "Launched Destiny 2."
    } catch {
        [System.Windows.MessageBox]::Show("Failed to launch destiny2.exe: $($_.Exception.Message)", "Launch Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

# Copy Log Button
$btnCopyLog.add_Click({
    try {
        [System.Windows.Clipboard]::SetText($txtConsole.Text)
        $btnCopyLog.Content = "Copied!"
        $resetTimer = New-Object System.Windows.Threading.DispatcherTimer
        $resetTimer.Interval = [TimeSpan]::FromSeconds(1.5)
        $resetTimer.add_Tick({
            $btnCopyLog.Content = "Copy Log"
            $resetTimer.Stop()
        })
        $resetTimer.Start()
    } catch {}
})

# Clear Log Button
$btnClearLog.add_Click({
    $txtConsole.Clear()
})

# --- Background Destiny 2 Process Poller ---
$procTimer = New-Object System.Windows.Threading.DispatcherTimer
$procTimer.Interval = [TimeSpan]::FromSeconds(2)
$procTimer.add_Tick({
    $running = $null -ne (Get-Process -Name destiny2 -ErrorAction SilentlyContinue)
    if ($running -ne $script:IsGameRunning) {
        $script:IsGameRunning = $running
        if ($running) {
            $procStatusDot.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
            $procStatusText.Text = "Destiny 2 is RUNNING (Close game to install/restore)"
            $procStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 252, 165, 165))
            $btnInstall.IsEnabled = $false
            $btnRestore.IsEnabled = $false
            $btnLaunchGame.IsEnabled = $false
        } else {
            $procStatusDot.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 34, 197, 94))
            $procStatusText.Text = "Destiny 2 is Closed"
            $procStatusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 148, 163, 184))
            Update-GameValidation
        }
    }
})

# --- Window Initialization ---
$window.add_Loaded({
    try {
        Load-ReleaseManifest
        Update-ToolStatus

        $saved = Get-SavedSettings
        if ($saved -and $saved.PSObject.Properties['LastDownloadDir'] -and $saved.LastDownloadDir) {
            $txtDownloadDir.Text = $saved.LastDownloadDir
        } else {
            $txtDownloadDir.Text = "C:\Games\Destiny 2"
        }

        if ($saved -and $saved.PSObject.Properties['LastSteamUser'] -and $saved.LastSteamUser) {
            $txtSteamUsername.Text = $saved.LastSteamUser
        }

        Update-DownloadDiskSpace

        $initialPath = Find-DestinyGameDirectory
        if ($initialPath) {
            $txtGameRoot.Text = $initialPath
        } else {
            Update-GameValidation
        }

        $procTimer.Start()
        Log-Message "[$(Get-Date -Format 'HH:mm:ss')] Dawn Installer & Downloader GUI initialized."
        Log-Message "Manifest: $script:ReleaseManifestPath"
        Log-Message "Installer Script: $script:InstallerScriptPath"
        Log-Message "Downloader Script: $script:DownloadScriptPath"
    } catch {
        try {
            Log-Message "[ERROR in startup]: $($_.Exception.Message)"
        } catch {}
    }
})

$window.add_Closing({
    param($sender, $e)
    if ($script:IsRunningInstaller -or $script:IsRunningDownload) {
        $res = [System.Windows.MessageBox]::Show("An installation or download operation is currently active!`nClosing the window now may interrupt file operations.`n`nAre you sure you want to exit?", "Warning: Active Operation", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($res -ne [System.Windows.MessageBoxResult]::Yes) {
            $e.Cancel = $true
            return
        }
    }
    $procTimer.Stop()
})

# Show Dialog
$null = $window.ShowDialog()
