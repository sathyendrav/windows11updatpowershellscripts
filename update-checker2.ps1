<#
.SYNOPSIS
    Advanced Update Reporter with Detailed Diagnostics and Optional Automation.

.DESCRIPTION
    This script provides comprehensive update checking and reporting across multiple platforms:
    - Microsoft Store apps (via CIM/WMI)
    - Winget packages (Windows Package Manager)
    - Chocolatey packages (Community Package Manager)
    
    Features:
    - Colorized console output for better readability
    - Optional automatic update installation
    - List-only mode for auditing
    - Installed software inventory from Windows Registry
    - System information display (OS, version, last boot time)
    - Recently installed applications report
    - Logging support for audit trails

.PARAMETER AutoUpdate
    When set, prompts the user to perform updates automatically.
    Applies to Winget packages with user confirmation.

.PARAMETER ListOnly
    When set, only lists available updates without offering installation.
    Useful for auditing and reporting purposes.

.PARAMETER ConfigPath
    Path to configuration file (default: config.json)

.PARAMETER NoLog
    Disable logging for this session

.NOTES
    File Name      : update-checker2.ps1
    Author         : sathyendrav
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges recommended
    Required Tools : Winget (App Installer), Chocolatey (optional)
    
.EXAMPLE
    .\update-checker2.ps1
    Runs in default mode - lists updates and installed software.

.EXAMPLE
    .\update-checker2.ps1 -ListOnly
    Explicitly lists updates only, no installation prompts.

.EXAMPLE
    .\update-checker2.ps1 -AutoUpdate
    Lists updates and prompts for automatic installation where supported.

.EXAMPLE
    .\update-checker2.ps1 -NoLog
    Run without logging.
#>

# ============================================================================
# Script Parameters
# ============================================================================
[CmdletBinding()]
param(
    [switch]$AutoUpdate,  # Enable automatic update prompts
    [switch]$ListOnly,    # List updates only, no installations
    [string]$ConfigPath = "$PSScriptRoot\config.json",  # Configuration file path
    [switch]$NoLog        # Disable logging
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
    $logFile = Initialize-Logging -LogDirectory $config.Logging.LogDirectory -ScriptName "update-checker2"
}

Write-Log "=" * 70 -Level "Info"
Write-Log "Windows Update Checker - Advanced Diagnostics" -Level "Info"
Write-Log "Parameters: AutoUpdate=$AutoUpdate, ListOnly=$ListOnly" -Level "Info"
Write-Log "=" * 70 -Level "Info"

# ============================================================================
# Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Writes colored output to the console for better visual organization.
.PARAMETER Message
    The text message to display.
.PARAMETER Color
    The foreground color for the text (default: White).
#>
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# ============================================================================
# Winget Update Checker Function
# ============================================================================

<#
.SYNOPSIS
    Checks for available Winget package updates and optionally installs them.
.DESCRIPTION
    Lists all packages with available upgrades using winget.
    If -AutoUpdate is enabled and -ListOnly is not set, prompts user to install updates.
#>
function Check-WingetUpdates {
    Write-Log "Checking Winget updates..." -Level "Info"
    
    # Verify winget is installed and accessible
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-ColorOutput -Message "`n=== Winget Packages ===" -Color "Cyan"
        
        try {
            # Query winget for available updates
            # --include-unknown: Shows packages even if their upgrade availability is uncertain
            $updates = winget upgrade --include-unknown | Out-String
            
            # Parse the output to determine if updates are available
            if ($updates -like "*No installed package*" -or $updates -like "*No applicable updates*") {
                Write-ColorOutput -Message "All Winget packages are up to date" -Color "Green"
                Write-Log "No Winget updates available" -Level "Info"
            } else {
                Write-ColorOutput -Message "Available updates found:" -Color "Yellow"
                # Display the list of available updates
                winget upgrade --include-unknown
                Write-Log "Winget updates found - see console output for details" -Level "Info"
                
                # If AutoUpdate is enabled and we're not in ListOnly mode, offer to install
                if ($AutoUpdate -and -not $ListOnly) {
                    $choice = Read-Host "`nDo you want to update all Winget packages? (Y/N)"
                    if ($choice -eq 'Y' -or $choice -eq 'y') {
                        Write-Log "User approved Winget package updates" -Level "Info"
                        # Upgrade all packages silently
                        winget upgrade --all --silent
                        Write-ColorOutput -Message "Winget packages updated successfully" -Color "Green"
                        Write-Log "Winget packages updated successfully" -Level "Success"
                    } else {
                        Write-Log "User declined Winget package updates" -Level "Info"
                    }
                }
            }
        } catch {
            # Handle any errors during winget operations
            Write-ColorOutput -Message "Error checking Winget updates: $($_.Exception.Message)" -Color "Red"
            Write-Log "Error checking Winget updates: $($_.Exception.Message)" -Level "Error"
        }
    } else {
        # Winget not found on the system
        Write-ColorOutput -Message "Winget is not available" -Color "Red"
        Write-Log "Winget is not available on this system" -Level "Warning"
    }
}

# ============================================================================
# Microsoft Store Update Checker Function
# ============================================================================

<#
.SYNOPSIS
    Triggers a Microsoft Store update scan.
.DESCRIPTION
    Uses CIM (Common Information Model) to access the MDM namespace and
    initiate a Store app update scan. Actual updates must be viewed/installed
    through the Microsoft Store app.
#>
function Check-StoreUpdates {
    Write-Log "Checking Microsoft Store updates..." -Level "Info"
    Write-ColorOutput -Message "`n=== Microsoft Store Apps ===" -Color "Cyan"
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-ColorOutput -Message "Skipping Store updates check - requires Administrator privileges" -Color "Yellow"
        Write-ColorOutput -Message "Run PowerShell as Administrator to check Microsoft Store updates" -Color "Yellow"
        Write-Log "Store updates check skipped - requires Administrator privileges" -Level "Warning"
        return
    }
    
    try {
        # Access MDM (Mobile Device Management) namespace to scan for Store updates
        # This triggers the update check but doesn't automatically install
        $result = Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" `
                                  -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" `
                                  -ErrorAction Stop | `
                  Invoke-CimMethod -MethodName UpdateScanMethod
        
        Write-ColorOutput -Message "Microsoft Store update scan initiated" -Color "Green"
        Write-Log "Microsoft Store update scan initiated successfully" -Level "Success"
        
        # Note: Store apps require the Microsoft Store app for viewing/installing updates
        Write-ColorOutput -Message "Check the Microsoft Store app for available updates" -Color "Yellow"
    } catch [Microsoft.Management.Infrastructure.CimException] {
        # Handle CIM-specific errors (permission denied, namespace not found, etc.)
        if ($_.Exception.Message -like "*Access denied*" -or $_.Exception.HResult -eq 0x80041003) {
            Write-ColorOutput -Message "Access denied to Microsoft Store update service" -Color "Red"
            Write-ColorOutput -Message "Please run PowerShell as Administrator to check Store updates" -Color "Yellow"
            Write-Log "Access denied to Microsoft Store update service" -Level "Error"
        } elseif ($_.Exception.Message -like "*Invalid namespace*") {
            Write-ColorOutput -Message "Microsoft Store MDM namespace not available on this system" -Color "Yellow"
            Write-ColorOutput -Message "This feature may not be supported on your Windows edition" -Color "Yellow"
            Write-Log "Microsoft Store MDM namespace not available" -Level "Warning"
        } else {
            Write-ColorOutput -Message "Error checking Store updates: $($_.Exception.Message)" -Color "Red"
            Write-Log "Error checking Store updates: $($_.Exception.Message)" -Level "Error"
        }
    } catch {
        # Handle other unexpected errors
        Write-ColorOutput -Message "Unexpected error checking Store updates: $($_.Exception.Message)" -Color "Red"
        Write-Log "Unexpected error checking Store updates: $($_.Exception.Message)" -Level "Error"
    }
}

# ============================================================================
# Chocolatey Update Checker Function
# ============================================================================

<#
.SYNOPSIS
    Checks for outdated Chocolatey packages.
.DESCRIPTION
    Uses 'choco outdated' to list packages that have newer versions available.
#>
function Check-ChocolateyUpdates {
    Write-Log "Checking Chocolatey updates..." -Level "Info"
    
    # Verify Chocolatey is installed and accessible
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-ColorOutput -Message "`n=== Chocolatey Packages ===" -Color "Cyan"
        
        try {
            # List all outdated Chocolatey packages
            # This command shows package name, current version, and available version
            choco outdated
            Write-Log "Chocolatey check completed - see console output for details" -Level "Info"
        } catch {
            # Handle any errors during Chocolatey operations
            Write-ColorOutput -Message "Error checking Chocolatey updates: $($_.Exception.Message)" -Color "Red"
            Write-Log "Error checking Chocolatey updates: $($_.Exception.Message)" -Level "Error"
        }
    } else {
        Write-Log "Chocolatey is not available on this system" -Level "Info"
    }
}

# ============================================================================
# Installed Software Inventory Function
# ============================================================================

<#
.SYNOPSIS
    Retrieves and displays installed software from the Windows Registry.
.DESCRIPTION
    Reads the Uninstall registry keys to build a comprehensive list of
    installed applications. Shows total count and recently installed apps.
#>
function Get-InstalledSoftware {
    Write-Log "Retrieving installed software inventory..." -Level "Info"
    Write-ColorOutput -Message "`n=== Installed Software Overview ===" -Color "Cyan"
    
    # Registry paths where installed software information is stored
    # Both native (64-bit) and WOW6432Node (32-bit on 64-bit systems) paths
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Query registry for installed applications
    # Filter out entries without DisplayName (incomplete/invalid entries)
    $installed = Get-ItemProperty $paths | 
                 Where-Object { $_.DisplayName } | 
                 Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    
    # Display total count of installed applications
    Write-ColorOutput -Message "Total installed applications: $($installed.Count)" -Color "White"
    Write-Log "Found $($installed.Count) installed applications" -Level "Info"
    
    # Show the 5 most recently installed applications
    $recent = $installed | Sort-Object InstallDate -Descending | Select-Object -First 5
    Write-ColorOutput -Message "`nRecently installed applications:" -Color "Yellow"
    # Format output as a table for readability
    $recent | Format-Table DisplayName, DisplayVersion, InstallDate -AutoSize
}

# ============================================================================
# Main Execution
# ============================================================================

Write-ColorOutput -Message "Windows 11 Application Update Checker" -Color "Magenta"
Write-ColorOutput -Message "=====================================" -Color "Magenta"

# Display system information
$os = Get-CimInstance Win32_OperatingSystem
Write-ColorOutput -Message "System: $($os.Caption)" -Color "White"
Write-ColorOutput -Message "Version: $($os.Version)" -Color "White"
Write-ColorOutput -Message "Last Boot: $($os.LastBootUpTime)" -Color "White"
Write-Log "System: $($os.Caption), Version: $($os.Version), Last Boot: $($os.LastBootUpTime)" -Level "Info"

# Execute all update checks in sequence
Check-WingetUpdates
Check-StoreUpdates
Check-ChocolateyUpdates
Get-InstalledSoftware

# Display completion message
Write-ColorOutput -Message ("`n" + ("=" * 60)) -Color "Magenta"
Write-ColorOutput -Message "Update check completed!" -Color "Green"
Write-Log "Update check completed successfully" -Level "Success"

# Indicate mode of operation
if ($AutoUpdate) {
    Write-ColorOutput -Message "Auto-update mode was enabled" -Color "Yellow"
}
if ($ListOnly) {
    Write-ColorOutput -Message "List-only mode - no updates were installed" -Color "Cyan"
}
Write-ColorOutput -Message ("=" * 60) -Color "Magenta"

if ($logFile) {
    Write-ColorOutput -Message "Log file: $logFile" -Color "Gray"
}

# Stop logging
Stop-Logging -LogFile $logFile