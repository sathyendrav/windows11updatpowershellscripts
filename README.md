<div align="center">

# 🔄 Windows Update Helper Scripts

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue?style=for-the-badge&logo=powershell)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge&logo=windows)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**Automate and manage Windows updates across multiple package managers**

[Features](#-features) • [Requirements](#-requirements) • [Installation](#-installation) • [Usage](#-usage) • [Scheduling](#-scheduling-optional)

</div>

---

## 📋 Overview

A collection of PowerShell scripts designed to streamline Windows system updates across multiple platforms:

- 🏪 **Microsoft Store** - Update Store apps
- 📦 **Winget** - Windows Package Manager
- 🍫 **Chocolatey** - Community package manager

Choose from simple one-click updates or advanced reporting tools with detailed diagnostics.

---

## 📂 Scripts

### 🚀 `install-updates.ps1` (Basic)
**Automated Update Installer**

Simple, hands-off script that runs Microsoft Store, Winget, and Chocolatey updates in fully automatic, non-interactive mode.

### 🌟 `install-updates-enhanced.ps1` (⭐ Recommended)
**Enhanced Automated Installer with Advanced Features**

Full-featured update installer with:
- 📝 **Comprehensive logging** with audit trails
- ⚙️ **Configuration file** support (`config.json`)
- 🛡️ **Pre-flight checks** (internet, disk space, admin rights)
- 📊 **HTML/CSV/JSON reports** generation
- 💾 **System restore points** before updates
- 🚫 **Package exclusions** support
- ⏱️ **Quiet hours** and scheduling options

### 🔍 `update-checker1.ps1`
**Quick Update Scanner**

Basic checker that displays available updates across all three platforms without installing them. Perfect for a quick overview.

### 📊 `update-checker2.ps1`
**Advanced Update Reporter**

Enhanced checker with comprehensive features:
- ✨ Colorized console output
- 🤖 Optional automatic updates
- 📝 List-only audit mode
- 📋 Installed software inventory
- 💻 System information display

### 🛠️ `UpdateUtilities.psm1`
**Shared Module Library**

PowerShell module providing common functions:
- Configuration management
- Logging and transcript handling
- Pre-flight system checks
- Report generation
- Restore point creation

---

## ✨ Features

### Core Features
- **🎯 Multi-Platform Support** - Manage updates from Store, Winget, and Chocolatey in one place
- **🎨 Colorized Output** - Easy-to-read console output with color coding
- **📊 Detailed Reporting** - View installed software, versions, and system info
- **⚙️ Flexible Modes** - List-only, auto-update, or manual confirmation
- **🔒 Safe Previews** - Test updates before committing changes
- **📅 Schedulable** - Easy integration with Task Scheduler

### Enhanced Features (New! 🎉)
- **📝 Comprehensive Logging** - Automatic transcript logs with timestamps and error tracking
- **⚙️ Configuration File** - Customize behavior via `config.json` (exclusions, settings, preferences)
- **🛡️ Pre-flight Checks** - Validates internet, disk space, admin rights, and update sources
- **📊 Report Generation** - Export results to HTML, CSV, or JSON formats
- **💾 System Restore Points** - Automatic safety checkpoints before major updates
- **🚫 Package Exclusions** - Exclude specific packages from updates
- **⏱️ Quiet Hours** - Respect configured quiet hours for automated runs
- **🔄 Retry Logic** - Automatic retry for failed updates
- **📧 Notifications** - Email and Windows notification support (configurable)

---

## 🔧 Requirements

| Component | Requirement | Notes |
|-----------|------------|-------|
| **OS** | Windows 10 / 11 | |
| **PowerShell** | 5.x or 7.x | |
| **Winget** | [App Installer](https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1) | Required for Winget updates |
| **Chocolatey** | [Chocolatey](https://chocolatey.org/install) | Optional, for Choco updates |
| **Permissions** | Administrator | Recommended for full functionality |

> 💡 **Tip:** Run these scripts in an elevated PowerShell session (`Run as Administrator`) to avoid permission issues.

> ⚠️ **IMPORTANT:** Review all scripts before running them. Understand what they do and ensure they meet your security and operational requirements.

---

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK**

These scripts are provided "AS IS" without warranty of any kind, express or implied. The author(s) and contributors:

- ❌ Make **NO WARRANTIES** regarding functionality, reliability, or suitability
- ❌ Accept **NO LIABILITY** for any damages, data loss, system issues, or other problems
- ❌ Are **NOT RESPONSIBLE** for misuse, misconfiguration, or unintended consequences
- ❌ Provide **NO SUPPORT GUARANTEES** or service level agreements

### 🛡️ Security & Safety

- **Test First:** Always test scripts in a non-production environment before deploying
- **Backup Data:** Create system backups before running automated updates
- **Review Code:** Inspect the script contents to ensure they align with your security policies
- **User Responsibility:** You are solely responsible for any consequences of running these scripts
- **System Changes:** These scripts modify your system by installing/updating software

### 📋 Recommended Practices

1. **Read the scripts** - Understand what they do before executing
2. **Test in safe environment** - Use a test machine or virtual machine first
3. **Create restore points** - Enable System Restore before major updates
4. **Backup critical data** - Protect important files and configurations
5. **Monitor execution** - Watch for errors or unexpected behavior
6. **Keep logs** - Document what was run and when for troubleshooting

### ⚖️ Legal Notice

- This software is licensed under the MIT License (see [LICENSE](LICENSE))
- Microsoft, Windows, PowerShell, Microsoft Store, and Winget are trademarks of Microsoft Corporation
- Chocolatey is a trademark of Chocolatey Software, Inc.
- No affiliation with or endorsement by Microsoft or Chocolatey is implied

---

## 🚀 Installation

1. **Clone or download this repository**
   ```powershell
   git clone https://github.com/sathyendrav/windows11updatpowershellscripts.git
   cd windows11updatpowershellscripts
   ```

2. **Review the scripts** (REQUIRED)
   ```powershell
   # Read each script to understand what it does
   Get-Content .\install-updates.ps1
   Get-Content .\update-checker1.ps1
   Get-Content .\update-checker2.ps1
   ```

3. **Set execution policy** (if needed)
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
   ⚠️ **Security Note:** Only change execution policy if you understand the implications and trust these scripts.

4. **You're ready to go!** 🎉
   
   ⚠️ **REMINDER:** Test on non-critical systems first!

---

## ⚙️ Configuration

The enhanced scripts use `config.json` for customization. Edit this file to control script behavior.

### Configuration File Structure

```json
{
  "UpdateSettings": {
    "EnableMicrosoftStore": true,      // Enable/disable Store updates
    "EnableWinget": true,              // Enable/disable Winget updates
    "EnableChocolatey": true,          // Enable/disable Chocolatey updates
    "CreateRestorePoint": true,        // Create restore point before updates
    "CheckDiskSpace": true,            // Verify sufficient disk space
    "MinimumFreeSpaceGB": 10          // Minimum free space required
  },
  "Logging": {
    "EnableLogging": true,             // Enable/disable logging
    "LogDirectory": ".\\logs",         // Where to store logs
    "MaxLogFiles": 10,                 // Max number of log files to keep
    "LogLevel": "Info"                 // Logging level
  },
  "PackageExclusions": {
    "Winget": [],                      // Packages to exclude from Winget updates
    "Chocolatey": []                   // Packages to exclude from Choco updates
  },
  "ReportSettings": {
    "GenerateReport": true,            // Auto-generate reports
    "ReportFormat": "HTML",            // Format: HTML, CSV, or JSON
    "ReportDirectory": ".\\reports"    // Where to store reports
  },
  "ScheduleSettings": {
    "QuietHoursStart": "22:00",        // Quiet hours start time
    "QuietHoursEnd": "07:00",          // Quiet hours end time
    "RespectQuietHours": false,        // Honor quiet hours
    "MaxRetryAttempts": 3              // Retry failed updates
  }
}
```

### Common Configuration Scenarios

**Exclude specific packages:**
```json
"PackageExclusions": {
  "Winget": ["Microsoft.Edge", "VideoLAN.VLC"],
  "Chocolatey": ["googlechrome", "firefox"]
}
```

**Disable specific update sources:**
```json
"UpdateSettings": {
  "EnableMicrosoftStore": true,
  "EnableWinget": true,
  "EnableChocolatey": false
}
```

**Change report format:**
```json
"ReportSettings": {
  "GenerateReport": true,
  "ReportFormat": "CSV",
  "ReportDirectory": "C:\\Reports\\Updates"
}
```

---

## 📖 Usage

### Option 1: `install-updates.ps1` - Basic (Legacy)

Simple hands-off automation without advanced features.

**Run it:**
```powershell
.\install-updates.ps1
```

---

### Option 2: `install-updates-enhanced.ps1` - ⭐ Recommended

Full-featured installer with logging, reporting, and safety features.

**Basic usage:**
```powershell
.\install-updates-enhanced.ps1
```

**With custom configuration:**
```powershell
.\install-updates-enhanced.ps1 -ConfigPath "C:\MyConfig\config.json"
```

**Skip restore point:**
```powershell
.\install-updates-enhanced.ps1 -SkipRestorePoint
```

**Force generate report:**
```powershell
.\install-updates-enhanced.ps1 -GenerateReport
```

**Features:**
1. ✅ Runs pre-flight checks (internet, disk space, admin rights)
2. 💾 Creates system restore point (optional)
3. 📝 Logs all operations to `.\logs\` directory
4. 🔄 Updates Microsoft Store, Winget, and Chocolatey
5. 📊 Generates HTML/CSV/JSON report (optional)
6. ✨ Respects package exclusions from config.json

**What it does:**
1. Loads configuration from `config.json`
2. Initializes logging and transcript
3. Runs pre-flight system checks
4. Creates system restore point (if enabled)
5. Triggers Microsoft Store update scan
2. Upgrades all Winget packages silently
3. Upgrades all Chocolatey packages silently

**Run it:**
```powershell
.\install-updates.ps1
```

**Behavior:**
- **Microsoft Store**: Uses `Get-CimInstance` with MDM App Management class
- **Winget**: Runs `winget upgrade --all` with silent flags
- **Chocolatey**: Runs `choco upgrade all -y`

---

### Option 2: `update-checker1.ps1` - Quick Preview

**What it does:**
- Lists available updates from all three platforms
- Safe preview mode - no installations performed

**Run it:**
```powershell
.\update-checker1.ps1
```

**Behavior:**
- **Winget**: Runs `winget upgrade` to list available updates
- **Chocolatey**: Runs `choco upgrade all --whatif` for dry-run preview

---

### Option 3: `update-checker2.ps1` - Advanced Reporting

#### Parameters

```powershell
param(
    [switch]$AutoUpdate,
    [switch]$ListOnly
)
```

| Parameter | Description |
|-----------|-------------|
| `-AutoUpdate` | Attempts to perform updates automatically instead of just listing |
| `-ListOnly` | Only lists updates without installing (useful for auditing) |

#### Key Features

- **📊 Check-WingetUpdates**: Uses `winget upgrade --include-unknown` to list/install updates
- **🏪 Check-StoreUpdates**: Triggers Microsoft Store app update scan via CIM
- **🍫 Check-ChocolateyUpdates**: Lists outdated Chocolatey packages
- **📦 Get-InstalledSoftware**: Reads registry for complete software inventory
- **💻 System Info**: Displays OS name, version, and last boot time

#### Examples

**Basic listing (no installations):**
```powershell
.\update-checker2.ps1
```

**Explicit list-only mode:**
```powershell
.\update-checker2.ps1 -ListOnly
```

**Automatic updates with full report:**
```powershell
.\update-checker2.ps1 -AutoUpdate
```

---

## 🛡️ Running Scripts Safely

### Step-by-Step Guide

1. **Open PowerShell as Administrator**
   - Press `Start` → type `powershell`
   - Right-click **Windows PowerShell** or **Windows Terminal**
   - Click **Run as administrator**

2. **Allow script execution** (first time only)
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Navigate to the script directory**
   ```powershell
   cd "d:\MySoftProjects\PowerShell\UpdateApps\windows11updatpowershellscripts"
   ```

4. **Run your desired script**
   ```powershell
   .\install-updates.ps1
   # OR
   .\update-checker1.ps1
   # OR
   .\update-checker2.ps1 -AutoUpdate
   ```

---

## 📅 Scheduling (Optional)

Automate updates with Windows Task Scheduler for hands-free maintenance.

### Setup Instructions

1. **Open Task Scheduler**
   - Press `Win + R` → type `taskschd.msc` → Enter

2. **Create Task**
   - Click **Create Task...**

3. **General Tab**
   - Name: `Windows Update Helper - Auto`
   - ✅ Check **Run with highest privileges**

4. **Triggers Tab**
   - Click **New...**
   - Set to **Daily** at your preferred time

5. **Actions Tab**
   - Click **New...** → **Start a program**
   - Program/script: `powershell.exe`
   - Add arguments:
     ```
     -ExecutionPolicy Bypass -File "d:\MySoftProjects\PowerShell\UpdateApps\windows11updatpowershellscripts\update-checker2.ps1" -AutoUpdate
     ```

6. **Save** the task

---

## 📁 Project Structure

```
windows11updatpowershellscripts/
├── config.json                      # Configuration file
├── install-updates.ps1              # Basic update installer
├── install-updates-enhanced.ps1     # ⭐ Enhanced installer with logging
├── update-checker1.ps1              # Quick update scanner
├── update-checker2.ps1              # Advanced update reporter
├── UpdateUtilities.psm1             # Shared module library
├── logs/                            # Execution logs (auto-created)
├── reports/                         # Generated reports (auto-created)
├── README.md                        # This file
├── TROUBLESHOOTING.md               # 🔧 Troubleshooting guide
└── LICENSE                          # MIT License
```

---

## 🔧 Troubleshooting

Having issues? Check our comprehensive troubleshooting guide:

### [📖 TROUBLESHOOTING.md](TROUBLESHOOTING.md)

Common issues covered:
- ❌ Execution policy errors
- ❌ Permission and access denied problems
- ❌ Microsoft Store update failures
- ❌ Winget not available or hanging
- ❌ Chocolatey installation issues
- ❌ Configuration and logging problems
- ❌ And much more...

### Quick Help

**Check log files:**
```powershell
Get-ChildItem .\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

**Verify configuration:**
```powershell
Get-Content .\config.json | ConvertFrom-Json
```

**Test prerequisites:**
```powershell
# Check if running as admin
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Test internet
Test-Connection google.com -Count 1

# Check winget
winget --version

# Check Chocolatey
choco --version
```

---

## ⚠️ Notes & Limitations

### Known Limitations

- **Microsoft Store updates** via CIM may depend on:
  - Windows edition (Home, Pro, Enterprise)
  - MDM / Store configuration
  - Organizational policies
  - Network connectivity
  
- **Winget and Chocolatey** updates can sometimes prompt for input or fail due to:
  - Package-specific constraints
  - Network or permission issues
  - Package repository availability
  - Dependency conflicts

### ⚠️ Critical Warnings

- **Production Systems:** Always test in `ListOnly` / preview modes (`update-checker1.ps1` or `update-checker2.ps1 -ListOnly`) before enabling automatic updates in production environments
- **Data Loss Risk:** Automated updates may cause application downtime or compatibility issues
- **System Stability:** Some updates may require system restarts or cause temporary instability
- **Network Usage:** Updates can consume significant bandwidth
- **No Rollback:** These scripts don't provide automatic rollback functionality
- **Third-Party Software:** Updates from Winget and Chocolatey are maintained by third parties

### 🔒 Security Considerations

- **Elevated Privileges:** These scripts may require administrator access
- **Code Execution:** Running scripts with elevated privileges carries security risks
- **Package Sources:** Verify package sources before installing
- **Malicious Updates:** No validation is performed on package authenticity by these scripts
- **Enterprise Environments:** Check with your IT department before using in corporate settings

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- 🐛 Report bugs
- 💡 Suggest new features
- 🔧 Submit pull requests

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### MIT License Summary

Permission is granted to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of this software, subject to the following conditions:

✅ **You MAY:**
- Use these scripts for personal or commercial purposes
- Modify and distribute modified versions
- Include in other projects

❌ **You MUST:**
- Include the original copyright notice and license
- Accept that the software is provided "AS IS" without warranty

⚠️ **The authors/contributors are NOT LIABLE for:**
- Any damages or losses resulting from use
- System failures, data loss, or security breaches
- Compatibility issues or conflicts
- Any claims, damages, or other liability

---

## 🙏 Acknowledgments

- Microsoft for [Winget](https://github.com/microsoft/winget-cli)
- [Chocolatey Software](https://chocolatey.org/) for the package manager
- The PowerShell community

---

<div align="center">

**Made with ❤️ for the Windows community**

[⬆ Back to Top](#-windows-update-helper-scripts)

</div>
