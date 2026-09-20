# Changelog

All notable changes to the **Dawn GUI Installer & Steam Depot Downloader** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v0.0.3] - 2026-09-20

### 🛠️ Changed
- **Folder Selection & Universal Portability**:
  - Removed personalized automatic drive scanning and Steam registry checks (`Find-DestinyGameDirectory`) to ensure portability across different PC configurations.
  - Removed the "Auto-Detect" button from the main Install tab. Users choose their game folder cleanly via the **Browse...** button or by downloading build 86657 directly via the integrated **Download Game Build** tab.
  - Previous game folder selections continue to be remembered across sessions on each machine via local user settings.

### 🐛 Fixed
- **Silent & Defensive Path Validation**:
  - Added strict error suppression and `DriveInfo.IsReady` checks for drive and path verifications across all tabs.
  - Systems lacking specific drive letters (e.g. secondary drives or network shares) will no longer emit drive lookup errors or console noise.

---

## [v0.0.2] - 2026-09-18

### 🌟 Added
- **Save-Preserving Update Logic (`-Update`)**:
  - Automatically detects existing Dawn save data (`player-state.db`), player identity, user preferences (`settings.json`), and custom scripts in the target Destiny 2 folder.
  - Dynamically exposes a `[x] Preserve existing saves, settings, and custom scripts (-Update)` checkbox (enabled by default when saves are detected).
  - Primary deployment button dynamically updates between **"Update Dawn"** (save preservation mode) and **"Install Dawn"** (clean profile mode).
  - Displays detected profile status in glowing emerald styling in the release information panel.
  - Added prompt to immediately apply updates while preserving saves when downloading a newer upstream release via the update banner.
  - Added milestone status tracking for save preservation in the live console stream.
- **Standalone Single-File Executable (`DawnInstaller.exe`)**:
  - Added [`Build-Executable.ps1`](file:///W:/Games/Destiny2_Sunrise/Dawn/Build-Executable.ps1) to compile `Install-Dawn-GUI.ps1` and embedded companion scripts into a native, standalone Win32 executable (`DawnInstaller.exe`, ~231 KB).
  - High-DPI aware, Single-Threaded Apartment (`-STA`) mode, no lingering console/command-prompt window, and embedded multi-resolution application icon (`dawn.ico`).
- **Steam Mobile QR Code Authentication**:
  - Embedded high-fidelity QR code display directly inside the **Download Game Build** tab.
  - Added automatic challenge refresh detection: when Steam updates the QR code challenge, the GUI automatically re-renders the new QR code without user intervention.
  - Seamless authentication transition: hides the QR code container and transitions into real-time download progress as soon as login is confirmed on the mobile app.
- **Steam Username & Credential Persistence**:
  - Added "Steam Username" configuration option alongside QR authentication.
  - Integrates `-remember-password` persistence so Depot 1085662 (binaries) reuses session tokens without prompting for a second login.
- **Automated Timestamped File Logging**:
  - Automatically writes all GUI and console activity to timestamped log files (`dawn-gui_log.yyyyMMdd.HHmmss.txt`).
  - Added **"Open Log File"** and **"Copy Log"** quick action buttons in the Console Logs tab.
- **Visual Interface Walkthrough**:
  - Added screenshots for all five GUI tabs to the documentation and `README.md`.

### 🛠️ Changed
- **Upstream Compatibility**: Full support for upstream Dawn 0.1.3 update routines without modifying upstream release files.
- **Release Packaging**: Updated [`package-release.ps1`](file:///W:/Games/Destiny2_Sunrise/Dawn/package-release.ps1) to package clean installer scripts, offline documentation, and build the standalone executable.
- **Documentation**: Updated `README.md` and `README-Installer.txt` with CLI update examples, save preservation guidelines, and quick-start instructions.

### 🐛 Fixed
- **WhatIf Simulation Crash**: Implemented a transparent PowerShell runner shim in the GUI to eliminate the upstream `ForEach-Object: The property 'Hash' cannot be found` error during `-WhatIf` dry-run simulations against backup directories.
- **Background Timer Variable Scoping**: Resolved dispatcher timer variable scoping issues in the background process watcher.
- **Encoding Purity**: Enforced strict 7-bit ASCII compatibility across all GUI scripts to prevent Windows PowerShell 5.1 parser encoding issues.

---

## [v0.0.1-alpha] - 2026-09-17

### 🌟 Initial Release
- **Modern WPF Dark-Themed GUI**: Custom gunmetal and Solar amber styling with High-DPI support.
- **Automated Game Detection**: Scans Steam libraries across all drives and adjacent directories for Destiny 2 Build 86657 (`86657.20.08.23.1800.d2_rc`).
- **Integrated Steam Depot Downloader**: Full GUI integration for downloading base game depots 1085661 and 1085662.
- **Backup & Rollback Manager**: Visual list of restore points in `<game>/.dawn/release-backups` with one-click restoration.
- **Interrupted Install Recovery**: Transaction journaling to detect and repair interrupted installations.
- **Live Upstream Release Checker**: Checks GitHub for newer Dawn releases with one-click in-place update.
- **Real-Time Console Stream**: Live milestone tracking and console output.
- **One-Click Game Launcher**: Launch Destiny 2 directly upon successful deployment.

---

[v0.0.3]: https://github.com/Skellums/D2Dawn-GUI-Installer/compare/v0.0.2...v0.0.3
[v0.0.2]: https://github.com/Skellums/D2Dawn-GUI-Installer/compare/v0.0.1-alpha...v0.0.2
[v0.0.1-alpha]: https://github.com/Skellums/D2Dawn-GUI-Installer/releases/tag/v0.0.1-alpha
