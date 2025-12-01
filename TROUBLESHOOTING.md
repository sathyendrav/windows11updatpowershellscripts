# 🔧 Troubleshooting Guide

Common issues and solutions for Windows Update Helper Scripts.

---

## Table of Contents

- [General Issues](#general-issues)
- [Microsoft Store Updates](#microsoft-store-updates)
- [Winget Issues](#winget-issues)
- [Chocolatey Issues](#chocolatey-issues)
- [Permission Problems](#permission-problems)
- [Configuration Issues](#configuration-issues)
- [Logging Issues](#logging-issues)
- [Notification Issues](#notification-issues)

---

## General Issues

### ❌ Script won't run - "Execution Policy" error

**Problem:**
```
... cannot be loaded because running scripts is disabled on this system.
```

**Solution:**
```powershell
# Option 1: Set execution policy for current user
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Option 2: Bypass for single execution
powershell.exe -ExecutionPolicy Bypass -File .\install-updates.ps1
```

---

### ❌ "Access Denied" or permission errors

**Problem:** Script fails with access denied messages.

**Solution:**
1. Right-click PowerShell and select **Run as Administrator**
2. Ensure your account has admin privileges
3. Check if antivirus is blocking the script

---

### ❌ Internet connectivity check fails

**Problem:** Pre-flight checks report no internet connection.

**Solution:**
```powershell
# Test your connection manually
Test-Connection -ComputerName google.com -Count 2

# Check if firewall is blocking
Test-NetConnection -ComputerName 8.8.8.8 -Port 53
```

**Workaround:** Edit `config.json` and set `CheckInternet` to `false` (not recommended).

---

### ❌ Low disk space warning

**Problem:** Script warns about insufficient disk space.

**Solution:**
1. Free up disk space using Disk Cleanup
2. Adjust minimum space requirement in `config.json`:
   ```json
   "MinimumFreeSpaceGB": 5
   ```

---

## Microsoft Store Updates

### ❌ "Failed to check Microsoft Store updates"

**Problem:**
```
Failed to check Microsoft Store updates: Access denied
```

**Solutions:**

1. **Run as Administrator** - Required for MDM namespace access

2. **Check Windows Store service:**
   ```powershell
   Get-Service -Name "InstallService" | Start-Service
   ```

3. **Reset Windows Store:**
   ```powershell
   wsreset.exe
   ```

4. **Verify MDM namespace:**
   ```powershell
   Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01"
   ```

---

### ❌ Store updates not showing

**Problem:** Script runs but no updates appear in Microsoft Store.

**Solution:**
- Wait 5-10 minutes for Store to process the update scan
- Open Microsoft Store app and manually check "Library" → "Get updates"
- The script only *triggers* the scan; Store app shows actual updates

---

## Winget Issues

### ❌ "Winget is not available"

**Problem:** Script reports Winget is not installed.

**Solutions:**

1. **Install App Installer from Microsoft Store:**
   - Open Microsoft Store
   - Search for "App Installer"
   - Click Install/Update

2. **Verify Winget installation:**
   ```powershell
   winget --version
   ```

3. **Add to PATH if installed but not found:**
   ```powershell
   $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
   ```

---

### ❌ Winget hangs or times out

**Problem:** Winget commands take too long or freeze.

**Solutions:**

1. **Update winget:**
   - Update "App Installer" in Microsoft Store

2. **Reset winget source:**
   ```powershell
   winget source reset --force
   ```

3. **Clear winget cache:**
   ```powershell
   Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_*\LocalCache\*" -Recurse -Force
   ```

---

### ❌ "Failed to install package" errors

**Problem:** Specific packages fail to update via Winget.

**Solutions:**

1. **Update package manually:**
   ```powershell
   winget upgrade <package-id>
   ```

2. **Add to exclusion list in `config.json`:**
   ```json
   "PackageExclusions": {
     "Winget": ["ProblematicPackage.Id"]
   }
   ```

3. **Check package logs:**
   ```powershell
   winget upgrade <package-id> --verbose
   ```

---

## Chocolatey Issues

### ❌ "Chocolatey is not available"

**Problem:** Script reports Chocolatey is not installed.

**Solutions:**

1. **Install Chocolatey (Run as Administrator):**
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
   iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

2. **Verify installation:**
   ```powershell
   choco --version
   ```

3. **Refresh environment variables:**
   ```powershell
   refreshenv
   # Or restart PowerShell
   ```

---

### ❌ Chocolatey package conflicts

**Problem:** Packages fail due to dependencies or conflicts.

**Solutions:**

1. **Update Chocolatey itself:**
   ```powershell
   choco upgrade chocolatey
   ```

2. **Force package reinstall:**
   ```powershell
   choco upgrade <package> --force
   ```

3. **Exclude problematic packages in `config.json`:**
   ```json
   "PackageExclusions": {
     "Chocolatey": ["problematic-package"]
   }
   ```

---

## Permission Problems

### ❌ Cannot create restore point

**Problem:** "Failed to create restore point" warning.

**Solutions:**

1. **Enable System Restore:**
   ```powershell
   Enable-ComputerRestore -Drive "C:\"
   ```

2. **Check if System Protection is enabled:**
   - Right-click "This PC" → Properties → System Protection
   - Ensure drive has protection enabled

3. **Skip restore point creation:**
   ```powershell
   .\install-updates-enhanced.ps1 -SkipRestorePoint
   ```

---

### ❌ Cannot create logs directory

**Problem:** Script fails to create logs folder.

**Solutions:**

1. **Check folder permissions:**
   ```powershell
   Test-Path ".\logs"
   New-Item -ItemType Directory -Path ".\logs" -Force
   ```

2. **Run from user directory:**
   ```powershell
   cd $HOME\Documents
   # Copy scripts here and run
   ```

---

## Configuration Issues

### ❌ Config.json not loading

**Problem:** Script uses defaults instead of config file.

**Solutions:**

1. **Verify config.json exists:**
   ```powershell
   Test-Path ".\config.json"
   Get-Content ".\config.json"
   ```

2. **Validate JSON syntax:**
   - Use online JSON validator (jsonlint.com)
   - Check for missing commas, brackets, or quotes

3. **Specify config path explicitly:**
   ```powershell
   .\install-updates-enhanced.ps1 -ConfigPath "C:\path\to\config.json"
   ```

---

### ❌ Invalid JSON in config file

**Problem:** Script errors: "Failed to load config.json"

**Solution:**
```powershell
# Test JSON validity
try {
    Get-Content ".\config.json" -Raw | ConvertFrom-Json
    Write-Host "JSON is valid" -ForegroundColor Green
} catch {
    Write-Host "JSON is invalid: $_" -ForegroundColor Red
}
```

**Common issues:**
- Trailing commas (not allowed in JSON)
- Unquoted property names
- Missing closing braces/brackets

---

## Logging Issues

### ❌ Transcript logging fails

**Problem:** "Failed to start transcript" warning.

**Solutions:**

1. **Check logs directory permissions:**
   ```powershell
   New-Item -ItemType Directory -Path ".\logs" -Force
   ```

2. **Close any open log files** - Can't write to locked files

3. **Disable logging in config.json:**
   ```json
   "Logging": {
     "EnableLogging": false
   }
   ```

---

### ❌ Log files too large

**Problem:** Log files consuming too much space.

**Solutions:**

1. **Clean old logs manually:**
   ```powershell
   Get-ChildItem ".\logs" -Filter "*.log" | 
     Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | 
     Remove-Item
   ```

2. **Adjust retention in config.json:**
   ```json
   "Logging": {
     "MaxLogFiles": 5,
     "MaxLogFileSizeKB": 2048
   }
   ```

---

## Performance Issues

### ❌ Script runs very slowly

**Problem:** Updates take excessive time.

**Solutions:**

1. **Check network speed:**
   ```powershell
   Test-Connection -ComputerName google.com -Count 10
   ```

2. **Disable parallel execution** (if enabled in future versions)

3. **Update only specific sources:**
   Edit `config.json`:
   ```json
   "UpdateSettings": {
     "EnableMicrosoftStore": false,
     "EnableWinget": true,
     "EnableChocolatey": false
   }
   ```

4. **Increase timeout in config:**
   ```json
   "Advanced": {
     "TimeoutSeconds": 7200
   }
   ```

---

## Getting Help

### Still having issues?

1. **Check log files:** `.\logs\install-updates-<timestamp>.log`

2. **Run with verbose output:**
   ```powershell
   .\install-updates-enhanced.ps1 -Verbose
   ```

3. **Test individual components:**
   ```powershell
   # Test Winget only
   winget upgrade --all
   
   # Test Chocolatey only
   choco upgrade all -y
   
   # Test Store access
   Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01"
   ```

4. **Open an issue on GitHub:**
   - Include error messages
   - Attach log files (remove sensitive info)
   - Describe steps to reproduce

5. **Check system requirements:**
   - Windows 10/11
   - PowerShell 5.1 or later
   - Administrator privileges
   - Active internet connection

---

## Quick Reference

### Essential Commands

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Check if running as admin
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Test internet
Test-Connection google.com

# Check winget
winget --version

# Check Chocolatey
choco --version

# View current execution policy
Get-ExecutionPolicy

# Test config.json
Get-Content .\config.json | ConvertFrom-Json
```

---

## Notification Issues

### ❌ Toast notifications not appearing

**Problem:** Script runs but no Windows toast notifications appear.

**Solution:**

1. **Check if notifications are enabled in config.json:**
   ```json
   "Notifications": {
     "EnableToastNotifications": true
   }
   ```

2. **Verify Windows notification settings:**
   - Open Settings > System > Notifications
   - Ensure "Get notifications from apps and other senders" is ON
   - Check Focus Assist settings (may block notifications)

3. **Test notifications manually:**
   ```powershell
   .\test-notifications.ps1
   ```

4. **Check Action Center:**
   - Press `Win + A` to open Action Center
   - Notifications may appear there even if toast didn't show

**Common Causes:**
- Focus Assist enabled (Do Not Disturb mode)
- Notification permissions disabled for PowerShell
- Windows notification service not running
- Running in Windows Server (limited notification support)

---

### ❌ Toast notifications show error in log

**Problem:** Log shows "Failed to send toast notification" warnings.

**Solution:**

1. **Windows Server:** Toast notifications may not be fully supported
2. **Older Windows 10:** Update to latest version (1809+)
3. **Run as regular user:** Some notification APIs work better without admin elevation
4. **Disable if problematic:**
   ```json
   "Notifications": {
     "EnableToastNotifications": false
   }
   ```

**Note:** Scripts will continue to work normally even if notifications fail. They provide additional feedback but are not required for core functionality.

---

**📧 For additional support, please open an issue on the [GitHub repository](https://github.com/sathyendrav/windows11updatpowershellscripts/issues).**
