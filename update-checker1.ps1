<#
.SYNOPSIS
    Quick Update Scanner - Lists available updates without installing them.

.DESCRIPTION
    This script scans for available updates across three package management platforms:
    - Microsoft Store apps (via CIM/WMI)
    - Winget packages (Windows Package Manager)
    - Chocolatey packages (Community Package Manager)
    
    This is a READ-ONLY preview mode - no updates are installed.
    Perfect for a quick overview of what needs updating.

.PARAMETER ConfigPath
    Path to configuration file (default: config.json)

.PARAMETER NoLog
    Disable logging for this session

.NOTES
    File Name      : update-checker1.ps1
    Author         : sathyendrav
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges recommended
    Required Tools : Winget (App Installer), Chocolatey (optional)
    
.EXAMPLE
    .\update-checker1.ps1
    Displays all available updates without installing them.

.EXAMPLE
    .\update-checker1.ps1 -NoLog
    Run without logging.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$NoLog
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# ============================================================================
# Initialize
# ============================================================================

# Load configuration
$config = Get-UpdateConfig -ConfigPath $ConfigPath

# Initialize logging
$logFile = $null
if (-not $NoLog -and $config -and $config.Logging.EnableLogging) {
    $logFile = Initialize-Logging -LogDirectory $config.Logging.LogDirectory -ScriptName "update-checker1"
}

Write-Log "=" * 70 -Level "Info"
Write-Log "Windows Update Checker - Quick Scanner" -Level "Info"
Write-Log "=" * 70 -Level "Info"

# ============================================================================
# Microsoft Store Updates Check
# ============================================================================
Write-Log "`nChecking for Microsoft Store app updates..." -Level "Info"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "Skipping Store updates check - requires Administrator privileges" -Level "Warning"
    Write-Log "Run PowerShell as Administrator to check Microsoft Store updates" -Level "Warning"
} else {
    try {
        # Access the MDM (Mobile Device Management) namespace to scan for Store app updates
        # This triggers an update check but does NOT automatically install updates
        Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" `
                        -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" `
                        -ErrorAction Stop | `
            Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
        
        Write-Log "Microsoft Store update scan initiated successfully" -Level "Success"
    } catch {
        Write-Log "Error checking Microsoft Store updates: $_" -Level "Error"
    }
}

# ============================================================================
# Winget (Windows Package Manager) Updates Check
# ============================================================================

# Verify that winget is installed and available in PATH
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Log "`nChecking for Winget package updates..." -Level "Info"
    
    try {
        # List all packages with available upgrades
        # This command only displays what CAN be updated - it does NOT install anything
        $wingetOutput = winget upgrade 2>&1 | Out-String
        Write-Log $wingetOutput -Level "Info"
        Write-Log "Winget check completed successfully" -Level "Success"
    } catch {
        Write-Log "Error checking Winget updates: $_" -Level "Error"
    }
} else {
    # Winget not found - notify user
    Write-Log "`nWinget is not available on this system" -Level "Warning"
    Write-Log "Install 'App Installer' from Microsoft Store to enable Winget" -Level "Info"
}

# ============================================================================
# Chocolatey Package Manager Updates Check
# ============================================================================

# Verify that Chocolatey is installed and available in PATH
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Log "`nChecking for Chocolatey package updates..." -Level "Info"
    
    try {
        # Dry-run mode: Shows what WOULD be upgraded without actually upgrading
        # --whatif: Simulates the upgrade operation without making any changes
        $chocoOutput = choco upgrade all --whatif 2>&1 | Out-String
        Write-Log $chocoOutput -Level "Info"
        Write-Log "Chocolatey check completed successfully" -Level "Success"
    } catch {
        Write-Log "Error checking Chocolatey updates: $_" -Level "Error"
    }
} else {
    # Chocolatey not found - silently skip
    Write-Log "`nChocolatey is not available on this system" -Level "Info"
}

# ============================================================================
# Completion Message
# ============================================================================
Write-Log "`n" + ("=" * 70) -Level "Info"
Write-Log "Update check completed!" -Level "Success"
Write-Log "No packages were installed - this was a preview only." -Level "Info"
Write-Log ("=" * 70) -Level "Info"

if ($logFile) {
    Write-Log "Log file: $logFile" -Level "Info"
}

# Stop logging
Stop-Logging -LogFile $logFile