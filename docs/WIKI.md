# Windows 11 Update PowerShell Scripts

This repository provides PowerShell scripts to help manage Windows Update tasks on Windows 11 systems. The scripts are intended to automate common update operations such as checking for available updates, installing updates, and troubleshooting Update issues.

> NOTE: These scripts are provided as-is. Run only on systems you control and test in a safe environment before production use. Always review scripts before executing them.

---

## Contents of this Wiki
- Overview
- Prerequisites
- Included scripts (how to discover them)
- Installation and quick start
- Usage examples
- Configuration and customization
- Troubleshooting
- Contributing
- License and contact

---

## Overview
This collection focuses on automating Windows Update tasks on Windows 11 using PowerShell. Depending on the scripts included in this repository, you can:
- Check Windows Update status
- Scan for available updates
- Download and install updates
- Handle reboots after updates
- Collect logs for troubleshooting

These scripts aim to be lightweight, transparent, and easy to modify.

## Prerequisites
- Windows 11 (supported builds may be documented per-script)
- PowerShell 5.1 (Windows PowerShell) or PowerShell 7+ (some scripts may only work on Windows PowerShell)
- Administrator privileges to run update and service-related commands
- ExecutionPolicy set to allow script execution for the session, for example:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Included scripts
The repository may contain multiple .ps1 scripts. Each script should contain a header comment describing its purpose, parameters and examples. To list scripts from the repository root:

```powershell
Get-ChildItem -Path . -Filter *.ps1 -Recurse | Select-Object FullName
```

Always read the top of each script before running it.

## Installation and quick start
1. Clone the repository:

```powershell
git clone https://github.com/sathyendrav/windows11-update-powershell-scripts.git
cd windows11-update-powershell-scripts
```

2. Open an elevated PowerShell session (Run as Administrator).

3. Allow script execution for the session if needed:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

4. Inspect a script before running:

```powershell
Get-Content .\scripts\Check-WindowsUpdate.ps1 -Head 100
```

5. Run a script (example):

```powershell
# Example: run a script with verbose output
.\scripts\Check-WindowsUpdate.ps1 -Verbose
```

Replace the example script path above with the actual script name or path in this repository.

## Usage examples

- Check for available updates:
```powershell
.\scripts\Check-WindowsUpdate.ps1
```

- Download and install updates (example, will vary per script):
```powershell
.\scripts\Install-WindowsUpdates.ps1 -AcceptAll -RebootIfRequired -Verbose
```

- Run with what-if / dry-run if the script exposes this mode:
```powershell
.\scripts\Install-WindowsUpdates.ps1 -WhatIf
```

- Schedule a script using Task Scheduler (example via PowerShell):
```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -WindowStyle Hidden -File "C:\path\to\scripts\Install-WindowsUpdates.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At 3am
Register-ScheduledTask -TaskName "AutoInstallWindowsUpdates" -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM"
```

## Configuration and customization
- Many scripts accept parameters for logging path, confirmation prompts, and reboot behavior. Check the script header or usage block for supported parameters.
- Logging: if scripts produce logs, they will usually write to a configurable path (example: %ProgramData%\WindowsUpdateScripts\Logs).
- Modify scripts to suit your environment (proxy, WSUS, offline scenarios). Keep a copy of the original if you customize.

## Troubleshooting
Common steps when updates fail or scripts encounter errors:
- Ensure the Windows Update service (wuauserv) and related services are running:

```powershell
Get-Service -Name wuauserv, bits, cryptsvc, msiserver
Start-Service -Name wuauserv
```
- Check Windows Update error codes in event logs:

```powershell
Get-WinEvent -LogName System -FilterXPath "*[EventData[contains(Data,'Windows Update')]]" -MaxEvents 50
```
- Inspect CBS and Windows Update logs:
  - Windows Update log: use `Get-WindowsUpdateLog` (creates readable .log from ETW)
  - CBS log: `%windir%\logs\cbs\cbs.log`
- Try component repairs:

```powershell
DISM /Online /Cleanup-Image /RestoreHealth
sfc /scannow
```
- If scripts fail due to permissions, run an elevated PowerShell prompt.
- For networking or WSUS issues, verify proxy settings, firewall, and WSUS server connectivity.

If a script produces an error you can't resolve, open an issue describing:
- Script name and path
- Exact command used
- Full error message and stack trace
- Relevant log excerpts

## Contributing
Contributions are welcome. Please follow these guidelines:
- Open an issue to discuss significant changes before implementing.
- Fork the repository and create a topic branch for your changes.
- Keep commits focused and descriptive.
- Add or update script header comments and examples when changing behavior.
- Include tests or reproduction steps for bug fixes where applicable.
- Submit a pull request describing the change, motivation, and testing performed.

Code style:
- Prefer clear, well-documented code.
- Avoid hard-coding paths; use parameters or environment-aware defaults.
- Keep scripts idempotent where possible.

## License and contact
See the repository LICENSE file for licensing terms (if present). For questions, bugs or feature requests, open an issue on the repository.

## Acknowledgements
Thank you for using and contributing to this collection. If you add scripts from external sources, please credit the original authors in the script headers.
