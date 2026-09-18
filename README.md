# Dawn GUI Installer & Depot Downloader

<p align="center">
  <img src="assets/dawndownload-logo.png" alt="Dawn Logo" width="128" height="128">
</p>

<p align="center">
  A modern, visual WPF graphical installer and Steam Depot Downloader for <a href="https://github.com/isinternets/Dawn">Dawn</a> (Destiny 2 Build 86657).
</p>

---

## 🌟 Overview

**Dawn GUI Installer** provides an interactive, dark-themed Windows graphical user interface (GUI) and companion CLI scripts designed to simplify acquiring Destiny 2 Build 86657 and deploying Dawn releases.

Built entirely using native **Windows PowerShell 5.1** and **WPF (XAML)**, it requires **zero external runtimes, Python, Node.js, or compiler toolchains**.

---

## ✨ Features

- **🎨 Modern Destiny / Dawn UI**: Custom dark gunmetal and Solar amber styling with full High-DPI scaling.
- **🔄 Upstream Release Checker & Live Auto-Updater**: Automatically queries GitHub for new releases from [isinternets/Dawn](https://github.com/isinternets/Dawn), compares against your local `release.json`, and offers one-click in-place update, direct ZIP download, or GitHub release viewing.
- **📥 Integrated Steam Depot Downloader**: Incorporates the official [Project Sunrise](https://projectsunrise.dev/guides/installing/) download process:
  - Depot `1085661` (Game Content, Manifest `7180122903232116872`, ~75 GB)
  - Depot `1085662` (Binaries, Manifest `2210332166360342287`, ~50 MB)
- **📱 Steam QR Code Authentication**: Login securely using your Steam Mobile App without typing credentials into the console. Saved session / password login is also supported.
- **🔍 Automated Game Detection**: Automatically searches Steam library paths across all local drives and adjacent directories for compatible Destiny 2 installations.
- **🛡️ Pre-Flight Validation**: Verifies `destiny2.exe` presence, file version (`86657.20.08.23.1800.d2_rc`), and write permissions.
- **⏱️ Live Process Watcher**: Monitors `destiny2.exe` execution in real time to prevent file collisions during installation or rollback.
- **🔄 Backup & Rollback Manager**: Browse historical release restore points in `<game>/.dawn/release-backups`, inspect installed versions and dates, and restore any backup with one click.
- **🚨 Transaction Recovery**: Detects interrupted installs using transaction journaling and prompts for instant one-click recovery.
- **🧪 Simulation Mode (-WhatIf)**: Preview all file deployment actions safely before making any modifications.
- **🚀 One-Click Game Launcher**: Launch Destiny 2 directly from the installer interface.
- **📋 Real-Time Console Streaming & Session Logging**: Live output feed with milestone indicators, automatic timestamped file logging (`dawn-gui_log.yyyyMMdd.HHmmss.txt`), and one-click clipboard copying.

---

## 📸 Interface & Tab Walkthrough

### 1. Install Dawn & Live Upstream Updates
The primary deployment interface verifies your Destiny 2 folder (`build 86657.20.08.23.1800.d2_rc`) and package payload. When a newer release is published on [isinternets/Dawn](https://github.com/isinternets/Dawn), the **Live Update System** automatically alerts you with an interactive notification banner featuring one-click **Update In-Place**, **Save ZIP**, or direct links to the GitHub release.

![Install Dawn Tab - Live Upstream Update](assets/01_installer-main.png)

### 2. Download Game Build (Steam Depot Downloader)
Acquires the clean base game build directly from Steam's CDN via DepotDownloader. Features embedded Steam Mobile App QR code authentication, credential persistence for seamless two-depot downloading, and a live drive space meter (~80–100 GB required).

![Download Game Build Tab](assets/02_depotdownloader.png)

### 3. Backups & Rollback Manager
Browse historical restore points stored in `<game>/.dawn/release-backups` with release tags, timestamps, and status pills. Restores clean backups with one click while safely preserving subsequent save progress in `after-restore`.

![Backups & Rollback Tab](assets/03_restorebackup.png)

### 4. Console Logs & File Logging
Real-time console stream with status milestones. Automatically writes timestamped session logs to disk (`dawn-gui_log.yyyyMMdd.HHmmss.txt`) and provides quick access via the **Open Log File**, **Copy Log**, and **Clear Console** buttons.

![Console Logs Tab](assets/04_console.png)

### 5. Guide & Info
Comprehensive built-in reference manual detailing depot manifests, display preferences (automatic Windowed Fullscreen configuration), rollback safety details, and project links.

![Guide & Info Tab](assets/05_helpinfo.png)

---

## 📋 System Requirements

- **Operating System**: Windows 10 or Windows 11 (64-bit)
- **PowerShell**: Windows PowerShell 5.1 (pre-installed on Windows 10/11)
- **Storage**: ~80–100 GB free disk space (if downloading the base game build)
- **Steam Account**: An account with Destiny 2 in its library (Destiny 2 is free on Steam)

---

## 🚀 Quick Start

### 1. Download the Installer
Clone this repository or download the ZIP from GitHub:
```cmd
git clone https://github.com/Skellums/D2Dawn-GUI-Installer.git
```

### 2. Using with an Official Dawn Release
1. Download and extract the latest Dawn release from [isinternets/Dawn Releases](https://github.com/isinternets/Dawn/releases).
2. Copy the contents of this repository into your extracted Dawn folder (alongside `Install-Dawn.ps1` and `release.json`).
3. Double-click **`Install-Dawn-GUI.cmd`** to open the visual installer.

### 3. If You Need to Download Destiny 2 Build 86657
1. Launch **`Install-Dawn-GUI.cmd`**.
2. Switch to the **Download Game Build** tab.
3. Select your target directory (e.g. `C:\Games\Destiny 2`).
4. Select **Steam Mobile App QR Code (Recommended)**.
5. Click **⬇ Download Destiny 2**.
6. Scan the QR code displayed in the GUI using your Steam Mobile App and confirm the sign-in.
7. The download will begin automatically and verify files once complete.

---

## 🖥️ Command-Line Interface (CLI)

If you prefer using the command line or scripting headless installations:

### Download Game Build:
```powershell
# Interactive batch launcher
.\Download-DestinyBuild.cmd

# PowerShell with Steam QR Code login
.\Download-DestinyBuild.ps1 -Destination "C:\Games\Destiny 2" -UseQrCode

# PowerShell with Steam username
.\Download-DestinyBuild.ps1 -Destination "C:\Games\Destiny 2" -SteamUsername "myaccount"
```

### Deploy Dawn:
```powershell
# Standard deployment
.\Install-Dawn.ps1 -GameRoot "C:\Games\Destiny 2"

# Simulation / Dry Run
.\Install-Dawn.ps1 -GameRoot "C:\Games\Destiny 2" -WhatIf

# Rollback latest backup
.\Install-Dawn.ps1 -GameRoot "C:\Games\Destiny 2" -Restore
```

---

## 📁 Repository Structure

| File / Folder | Description |
| :--- | :--- |
| `Install-Dawn-GUI.ps1` | Core WPF graphical user interface script |
| `Install-Dawn-GUI.cmd` | Windows batch launcher for the GUI (`-STA` mode, hidden shell) |
| `Download-DestinyBuild.ps1` | Standalone CLI script for Steam DepotDownloader |
| `Download-DestinyBuild.cmd` | Windows batch runner for CLI depot downloading |
| `README-Installer.txt` | Plain-text reference manual for offline viewing |
| `assets/` | Project branding logo and tab interface screenshots |
| `LICENSE` | GNU General Public License v3.0 |

---

## 🔒 Safety & Recovery Details

- **Transactional Journaling**: All file copy and replacement actions are tracked in a transaction log. If an installation is cancelled or unexpectedly interrupted, the installer automatically detects it upon next launch and offers instant rollback.
- **Safe Archival**: Any modifications or saves created since installation are retained inside the backup's `after-restore` directory, ensuring your progress is never overwritten.
- **Non-Destructive**: Existing Sunrise or Restoration folders remain completely untouched.

---

## 🙏 Credits & Acknowledgements

- **[Dawn](https://github.com/isinternets/Dawn)** by [isinternets](https://github.com/isinternets)
- **[Project Sunrise](https://projectsunrise.dev)** for the archive manifests and installation guides
- **[DepotDownloader](https://github.com/SteamRE/DepotDownloader)** by [SteamRE](https://github.com/SteamRE)
