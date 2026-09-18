DAWN INSTALLER & GUI GUIDE
===========================

OVERVIEW
--------
This package provides both a modern, dark-themed visual graphical user interface (GUI) 
and scriptable command-line interfaces (CLI) to acquire Destiny 2 build 86657 via Steam
and install the Dawn release over it.

No build tools, compilers, Python, or external packages are required. The GUI runs 
natively on Windows 10 and 11 using built-in Windows PowerShell 5.1 and WPF.


QUICK START (VISUAL GUI)
------------------------
1. Extract the release package completely into a folder (e.g., your Downloads folder).
2. Ensure Destiny 2 is closed.
3. Double-click "Install-Dawn-GUI.cmd".
4. If you already have Destiny 2 build 86657:
   - The installer automatically searches for compatible Destiny 2 installations.
   - Or click "Browse..." to select your destiny2.exe.
   - Click "Install Dawn" to deploy the release.
5. If you do NOT have Destiny 2 build 86657:
   - Switch to the "Download Game Build" tab.
   - Select your desired destination directory (requires ~80-100 GB of free storage).
   - Select "Steam Mobile App QR Code" (recommended: no password needed, just scan with phone).
   - Click "Download Destiny 2".
   - Once the download completes, it will automatically verify the build and configure the installer.
6. Click "Launch Destiny 2" to start the game!


STEAM DEPOT DOWNLOADER (INTEGRATED)
-----------------------------------
The installer incorporates the Project Sunrise Steam Depot Downloader workflow
(see https://projectsunrise.dev/guides/installing/):

- Downloads the exact clean base build: 86657.20.08.23.1800.d2_rc
- Downloads both required depots:
  * Depot 1085661 (Content Depot, Manifest 7180122903232116872, ~75 GB)
  * Depot 1085662 (Binaries Depot, Manifest 2210332166360342287, ~50 MB)
- Supports Steam Mobile App QR login or username/password authentication.
- Automatically saves login credentials (-remember-password) so only one authentication is needed.
- Resumable: If a download is paused or interrupted, running it again resumes where it left off.
- Live disk space calculator warns if available storage is below 100 GB.
- Built-in DepotDownloader runner and auto-extractor from tools/DepotDownloader.


GUI FEATURES
------------
- Modern Destiny/Dawn Theme: Dark gunmetal and Solar amber styling with full High-DPI support.
- Built-in Steam Depot Downloader: Download the required Destiny 2 build directly in the GUI.
- Game Auto-Detection: Automatically scans sibling game directories, Steam libraries across
  all configured drives, and previous sessions.
- Pre-Flight Validation: Verifies that destiny2.exe exists and matches build 86657.20.08.23.1800.d2_rc.
- Live Process Watcher: Detects if Destiny 2 is running and prevents concurrent modifications.
- Real-Time Console Streaming: Displays live installation progress, milestones, and hash verifications
  without freezing or blocking the UI.
- Simulation / Dry Run: Check "Dry Run / Simulation Mode (-WhatIf)" to preview all actions safely.
- Backup & Rollback Manager:
  * Lists all restore points in <game>\.dawn\release-backups.
  * Shows release versions, human-readable dates, and status pills (Installed, Rolled Back, Interrupted).
  * One-click restore of any selected backup.
  * Preserves newly created progress since installation inside the backup's after-restore folder.
- Interrupted Install Recovery: Detects incomplete or interrupted transactions and prompts you with
  a single-click recovery button.
- Upstream Release Updates:
  * Automatically queries GitHub (https://github.com/isinternets/Dawn) for newer Dawn releases.
  * Displays release notification badge and banner with release notes and publish date.
  * In-place update: Automatically downloads and updates release.json, payload files, and scripts.
  * Save ZIP: Save the latest release archive to any location.
  * One-click manual "Check Updates" button.
- One-Click Game Launcher: Launch Destiny 2 directly from the installer once completed.
- Log Tools: One-click "Copy Log" to clipboard for easy troubleshooting and support.


COMMAND-LINE USAGE (CLI)
------------------------
If you prefer the command line, standalone CLI scripts are also provided:

1. Download Destiny 2 Build 86657:
   - Interactive / Batch:
       .\Download-DestinyBuild.cmd

   - PowerShell with QR Code Login:
       .\Download-DestinyBuild.ps1 -Destination "C:\Games\Destiny 2" -UseQrCode

   - PowerShell with Steam Username:
       .\Download-DestinyBuild.ps1 -Destination "C:\Games\Destiny 2" -SteamUsername "myaccount"

2. Install Dawn over Game:
   - Standard Install:
       .\Install-Dawn.ps1 -GameRoot "C:\Path\To\Destiny 2"

   - Dry Run (Simulation):
       .\Install-Dawn.ps1 -GameRoot "C:\Path\To\Destiny 2" -WhatIf

   - Rollback Latest Backup:
       .\Install-Dawn.ps1 -GameRoot "C:\Path\To\Destiny 2" -Restore

   - Rollback Specific Backup:
       .\Install-Dawn.ps1 -GameRoot "C:\Path\To\Destiny 2" -Restore -BackupPath "C:\Path\To\Destiny 2\.dawn\release-backups\<timestamp-guid>"


IMPORTANT NOTES
---------------
1. Steam Account Requirement: Destiny 2 is free on Steam, but your Steam account must have added
   Destiny 2 to its library to authorize depot downloads.
2. Storage: The base game build requires approximately 80 to 100 GB of free disk space.
3. Fresh Save Profile: Every installation starts a fresh profile using the release defaults.
   Existing progress, settings, identity, and custom scripts from earlier Dawn installs are not
   carried over, but are preserved in the backup folder.
4. Isolated Directories: Old Sunrise and Restoration directories are left completely intact
   and are never imported or modified.
5. Display Mode: The installer sets Windowed Fullscreen as the launch default in the user's
   cvar preferences. Resolution and graphics quality settings are preserved.
6. Requirements: Requires Windows 10 or 11 (64-bit) and Windows PowerShell 5.1 (built into Windows)
   or newer.
