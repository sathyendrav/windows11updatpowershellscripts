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

### 🚀 `install-updates.ps1`
**Automated Update Installer**

Runs Microsoft Store, Winget, and Chocolatey updates in fully automatic, non-interactive mode.

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

---

## ✨ Features

- **🎯 Multi-Platform Support** - Manage updates from Store, Winget, and Chocolatey in one place
- **🎨 Colorized Output** - Easy-to-read console output with color coding
- **📊 Detailed Reporting** - View installed software, versions, and system info
- **⚙️ Flexible Modes** - List-only, auto-update, or manual confirmation
- **🔒 Safe Previews** - Test updates before committing changes
- **📅 Schedulable** - Easy integration with Task Scheduler

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

---

## 🚀 Installation

1. **Clone or download this repository**
   ```powershell
   git clone https://github.com/sathyendrav/windows11updatpowershellscripts.git
   cd windows11updatpowershellscripts
   ```

2. **Set execution policy** (if needed)
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **You're ready to go!** 🎉

---

## 📖 Usage

### Option 1: `install-updates.ps1` - Hands-Off Automation

**What it does:**
1. Triggers Microsoft Store update scan
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

## ⚠️ Notes & Limitations

- **Microsoft Store updates** via CIM may depend on:
  - Windows edition
  - MDM / Store configuration
  
- **Winget and Chocolatey** updates can sometimes prompt for input or fail due to:
  - Package-specific constraints
  - Network or permission issues

- **Always test** in `ListOnly` / preview modes (`update-checker1.ps1` or `update-checker2.ps1 -ListOnly`) before enabling automatic updates in production environments.

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- 🐛 Report bugs
- 💡 Suggest new features
- 🔧 Submit pull requests

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

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
