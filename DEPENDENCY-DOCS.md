# 📦 Dependency Installation Documentation

Complete documentation for the Dependency Installation feature.

## Overview

The dependency installation system automatically detects and installs required package managers and PowerShell modules before running updates.

## Features

- **🔍 Automatic Detection** - Checks if Winget, Chocolatey, and PowerShell modules are installed
- **📥 Auto-Installation** - Automatically installs missing dependencies
- **📊 Version Checking** - Verifies minimum version requirements are met
- **⚙️ Multiple Install Methods** - Microsoft Store, GitHub, or web installation
- **✅ Post-Install Validation** - Confirms successful installation
- **🔄 Configurable Behavior** - Control which dependencies are required and how to handle failures

## Configuration

Edit `config.json` to customize dependency installation:

```json
{
  "DependencyInstallation": {
    "EnableDependencyCheck": true,
    "AutoInstallMissingDependencies": true,
    "RequiredDependencies": {
      "Winget": true,
      "Chocolatey": false,
      "PowerShellModules": []
    },
    "MinimumVersions": {
      "Winget": "1.6.0",
      "Chocolatey": "2.0.0",
      "PowerShell": "5.1"
    },
    "InstallationMethods": {
      "Winget": "MicrosoftStore",
      "Chocolatey": "WebInstall",
      "PowerShellModules": "PSGallery"
    },
    "SkipDependencyCheck": false,
    "FailOnMissingDependencies": false,
    "InstallationTimeout": 300,
    "ValidateAfterInstallation": true,
    "LogDependencyStatus": true
  }
}
```

## Configuration Options

- **EnableDependencyCheck** - Enable/disable dependency checking
- **AutoInstallMissingDependencies** - Automatically install missing dependencies
- **RequiredDependencies** - Specify which package managers and modules are required
- **MinimumVersions** - Define minimum version requirements
- **InstallationMethods** - Choose installation method for each dependency
- **SkipDependencyCheck** - Skip dependency check entirely
- **FailOnMissingDependencies** - Stop execution if dependencies are missing
- **InstallationTimeout** - Maximum time in seconds for installation
- **ValidateAfterInstallation** - Verify installation succeeded
- **LogDependencyStatus** - Log detailed dependency status

## Installation Methods

### Winget Installation Methods

- **MicrosoftStore** - Install via Microsoft Store (App Installer package)
- **GitHub** - Download and install from GitHub releases

### Chocolatey Installation

- **WebInstall** - Standard web-based installation script from chocolatey.org

### PowerShell Modules

- **PSGallery** - Install from PowerShell Gallery (requires internet)
- **CurrentUser** - Install for current user only (no admin required)
- **AllUsers** - Install for all users (requires admin rights)

## Required PowerShell Modules

Specify PowerShell modules that must be installed:

```json
"RequiredDependencies": {
  "Winget": true,
  "Chocolatey": true,
  "PowerShellModules": [
    "PSReadLine",
    "PowerShellGet",
    "Pester"
  ]
}
```

## Using Dependency Functions

```powershell
# Check if Winget is installed
$wingetInstalled = Test-WingetInstalled

# Check if Chocolatey is installed
$chocoInstalled = Test-ChocolateyInstalled

# Check PowerShell module
$moduleInstalled = Test-PowerShellModule -ModuleName "PSReadLine" -MinimumVersion "2.2.0"

# Get Winget version
$wingetVersion = Get-WingetVersion

# Get Chocolatey version
$chocoVersion = Get-ChocolateyVersion

# Check version requirement
$versionOk = Test-DependencyVersion -Dependency "Winget" -MinimumVersion "1.6.0"

# Install Winget
$success = Install-WingetCLI -Method "MicrosoftStore" -TimeoutSeconds 300

# Install Chocolatey
$success = Install-Chocolatey -TimeoutSeconds 300

# Install PowerShell module
$success = Install-PowerShellModule -ModuleName "Pester" `
  -MinimumVersion "5.0.0" -Scope "CurrentUser"

# Install specific dependency
$success = Install-Dependency -DependencyType "Winget" `
  -InstallationOptions @{ Method = "GitHub"; Timeout = 300 }

# Run complete dependency check
$result = Invoke-DependencyInstallation

# Check results
if ($result.Success) {
  Write-Host "All dependencies satisfied"
  foreach ($dep in $result.Dependencies) {
    Write-Host "$($dep.Dependency): $($dep.Action)"
  }
}
```

## Dependency Check Results

The `Invoke-DependencyInstallation` function returns:

```powershell
@{
  Success = $true/$false
  Message = "Status message"
  Dependencies = @(
    @{
      Dependency = "Winget"
      Required = $true
      Installed = $true
      VersionOk = $true
      Action = "AlreadyInstalled"|"Installed"|"NotInstalled"
      Success = $true/$false
    }
  )
}
```

## Failure Handling

### Continue on Missing Dependencies (Default)

```json
"FailOnMissingDependencies": false
```

Script continues even if dependencies are missing. Warnings are logged.

### Fail on Missing Dependencies

```json
"FailOnMissingDependencies": true
```

Script stops execution if required dependencies are missing or cannot be installed.

## Common Scenarios

### Scenario 1: Fresh Windows Installation

- Winget not installed → Auto-install from Microsoft Store
- Chocolatey not installed → Auto-install via web script
- PowerShell 5.1+ detected → Continue

### Scenario 2: Corporate Environment

- Winget installed but outdated → Upgrade to minimum version
- Chocolatey blocked by policy → Skip Chocolatey updates
- Required modules missing → Auto-install from PSGallery

### Scenario 3: Manual Control

```json
"EnableDependencyCheck": true,
"AutoInstallMissingDependencies": false,
"FailOnMissingDependencies": true
```

Check dependencies but don't install automatically. Fail if missing.

## Best Practices

1. **Enable Dependency Check** - Always check dependencies before updates
2. **Set Minimum Versions** - Specify minimum versions to avoid compatibility issues
3. **Use MicrosoftStore for Winget** - More reliable than GitHub method
4. **Test Timeout Values** - Adjust timeout based on network speed
5. **Log Dependency Status** - Keep logs for troubleshooting
6. **Validate After Install** - Always verify installation succeeded
7. **Corporate Environments** - May need to disable auto-install and pre-install manually
8. **PowerShell Modules** - Use CurrentUser scope to avoid admin requirements

## Troubleshooting

### Winget Installation Fails

- Ensure Windows 10/11 (Winget requires Windows 10 1809+)
- Check Microsoft Store connectivity
- Try GitHub method if Store method fails
- Manually install from: https://aka.ms/getwinget

### Chocolatey Installation Fails

- Check execution policy: `Get-ExecutionPolicy`
- Ensure internet connectivity to chocolatey.org
- Run as Administrator
- Check firewall/proxy settings

### PowerShell Module Installation Fails

- NuGet provider may need manual installation
- PSGallery must be accessible (corporate networks may block)
- Check available disk space
- Verify PowerShellGet module is installed

### Version Check Fails

- Command may be in PATH but not refreshed
- Restart PowerShell session after installation
- Refresh environment variables: `$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")`

## Function Reference

### Test-WingetInstalled

Checks if Windows Package Manager (Winget) is installed.

**Returns:** `$true` if installed, `$false` otherwise

### Test-ChocolateyInstalled

Checks if Chocolatey package manager is installed.

**Returns:** `$true` if installed, `$false` otherwise

### Test-PowerShellModule

Checks if a PowerShell module is installed.

**Parameters:**
- `ModuleName` (required) - Name of the module
- `MinimumVersion` (optional) - Minimum required version

**Returns:** `$true` if installed (and meets version requirement), `$false` otherwise

### Get-WingetVersion

Gets the installed version of Winget.

**Returns:** Version object or `$null`

### Get-ChocolateyVersion

Gets the installed version of Chocolatey.

**Returns:** Version object or `$null`

### Test-DependencyVersion

Checks if a dependency meets minimum version requirements.

**Parameters:**
- `Dependency` (required) - "Winget", "Chocolatey", or "PowerShell"
- `MinimumVersion` (required) - Minimum required version

**Returns:** `$true` if version meets requirement, `$false` otherwise

### Install-WingetCLI

Installs Windows Package Manager (Winget).

**Parameters:**
- `Method` (optional) - "MicrosoftStore" or "GitHub" (default: "MicrosoftStore")
- `TimeoutSeconds` (optional) - Timeout in seconds (default: 300)

**Returns:** `$true` if successful, `$false` otherwise

### Install-Chocolatey

Installs Chocolatey package manager.

**Parameters:**
- `TimeoutSeconds` (optional) - Timeout in seconds (default: 300)

**Returns:** `$true` if successful, `$false` otherwise

### Install-PowerShellModule

Installs a PowerShell module from PSGallery.

**Parameters:**
- `ModuleName` (required) - Name of the module
- `MinimumVersion` (optional) - Minimum version to install
- `Scope` (optional) - "CurrentUser" or "AllUsers" (default: "CurrentUser")
- `TimeoutSeconds` (optional) - Timeout in seconds (default: 300)

**Returns:** `$true` if successful, `$false` otherwise

### Install-Dependency

Installs a specific dependency.

**Parameters:**
- `DependencyType` (required) - "Winget", "Chocolatey", or "PowerShellModule"
- `ModuleName` (optional) - Required if DependencyType is "PowerShellModule"
- `MinimumVersion` (optional) - Minimum version to install
- `InstallationOptions` (optional) - Hashtable with options (Method, Timeout, Scope)

**Returns:** `$true` if successful, `$false` otherwise

### Invoke-DependencyInstallation

Checks and installs all required dependencies based on configuration.

**Parameters:**
- `Config` (optional) - Configuration hashtable (uses Get-UpdateConfig if not provided)

**Returns:** Hashtable with Success, Message, and Dependencies array
