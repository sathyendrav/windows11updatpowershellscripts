# Windows Update Helper Scripts

This repository contains PowerShell scripts to help check for and install updates on Windows systems via:

- **Microsoft Store**
- **Winget**
- **Chocolatey**

It includes both simple “fire-and-forget” scripts and a more advanced reporting script.

---

## Contents

- `install-updates.ps1`  
  Runs Microsoft Store, Winget, and Chocolatey updates in **non-interactive / automatic** mode where possible.

- `update-checker1.ps1`  
  Basic **update checker** that shows what can be updated via Microsoft Store, Winget, and Chocolatey.  
  (Does not perform silent installs; good for a quick overview.)

- `update-checker2.ps1`  
  Enhanced **update checker with detailed reporting**:
  - Colorized console output
  - Optional automatic updates
  - Optional “list only” mode
  - Summary of installed software via registry
  - Basic system info (OS name, version, last boot time)

---

## Requirements

- Windows 10 / 11
- PowerShell (5.x or 7.x)
- For Winget updates:
  - [App Installer](https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1) must be installed
- For Chocolatey updates:
  - [Chocolatey](https://chocolatey.org/install) must be installed and available as `choco` in `PATH`
- To check Microsoft Store app updates:
  - Script must be run with sufficient privileges (typically **Run as Administrator**)
  - Access to the `Root\cimv2\mdm\dmmap` CIM namespace

> 💡 **Recommendation:** Run these scripts in an elevated PowerShell session (`Run as Administrator`) to avoid permission issues.

---

## Usage

### 1. `install-updates.ps1`

This is the most “hands-off” script. It:

1) Triggers a Microsoft Store update scan  
2) Upgrades all available Winget packages silently  
3) Upgrades all Chocolatey packages silently  

#### Run

```powershell
# From the folder where the script is stored:
.\install-updates.ps1
