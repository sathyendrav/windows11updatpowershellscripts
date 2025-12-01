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


Behavior:

Microsoft Store
Uses Get-CimInstance on the MDM App Management class and calls UpdateScanMethod.

Winget
Runs:

winget upgrade


to list available upgrades.

Chocolatey
Runs:

choco upgrade all --whatif


so you can see what would be updated without actually changing anything.

Use this as a safe preview before running the more aggressive install-updates.ps1.

3. update-checker2.ps1

An enhanced checker with better reporting and optional automation.

Parameters
param(
    [switch]$AutoUpdate,
    [switch]$ListOnly
)


-AutoUpdate
When set, the script (where implemented) will attempt to perform updates automatically instead of only listing them.

-ListOnly
When set, the script will only list potential updates without installing them (useful for auditing).

If both switches are omitted, the script defaults to a reporting / listing mode.

Features

Colorized output via Write-ColorOutput helper function

Check-WingetUpdates
Uses winget upgrade --include-unknown to list or install updates, depending on switches

Check-StoreUpdates
Triggers Microsoft Store app update scan via CIM

Check-ChocolateyUpdates
Lists outdated Chocolatey packages (and may be extended to install them in auto mode)

Get-InstalledSoftware
Reads installed applications from:

HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*

HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*
and prints out name, version, publisher, and install date, plus a total count.

System info summary
Uses Get-CimInstance Win32_OperatingSystem to display:

OS Caption (name)

Version

Last boot time

At the end, it prints a final “Update check completed!” message and indicates whether -AutoUpdate was enabled.

Run – examples

Basic listing (no installs):

.\update-checker2.ps1


List only (explicit):

.\update-checker2.ps1 -ListOnly


Attempt automatic updates + full report:

.\update-checker2.ps1 -AutoUpdate


List only, but still show installed software and system info:

.\update-checker2.ps1 -ListOnly

Running the Scripts Safely

Open PowerShell as Administrator

Press Start → type powershell

Right-click Windows PowerShell or Windows Terminal

Click Run as administrator

Allow script execution (if needed)
If scripts are blocked by execution policy:

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser


Navigate to the script directory

cd "C:\Path\To\Repo"


Run the desired script (examples)

.\install-updates.ps1
.\update-checker1.ps1
.\update-checker2.ps1 -AutoUpdate

Scheduling with Task Scheduler (Optional)

To automate updates (for example, daily):

Open Task Scheduler

Click Create Task…

On General:

Name: Windows Update Helper – Auto

Check Run with highest privileges

On Triggers:

New → set to Daily, choose time

On Actions:

New → Start a program

Program/script: powershell.exe

Add arguments:

-ExecutionPolicy Bypass -File "C:\Path\To\Repo\update-checker2.ps1" -AutoUpdate


Save the task.

Notes & Limitations

Microsoft Store updates via CIM may depend on:

Windows edition

MDM / Store configuration

Winget and Chocolatey updates can sometimes prompt for input or fail due to:

Package-specific constraints

Network or permission issues

Always test in ListOnly / preview modes (update-checker1.ps1 or update-checker2.ps1 -ListOnly) before enabling automatic updates in production environments.

License

Add your preferred license here (e.g., MIT, Apache 2.0, etc.).


If you’d like, I can also generate separate `docs/*.md` files per script (e.g., `docs/install-updates.md`, `docs/update-checker2.md`) or add header comments to each `.ps1` with short usage notes.