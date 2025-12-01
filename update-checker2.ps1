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

.PARAMETER AutoUpdate
    When set, prompts the user to perform updates automatically.
    Applies to Winget packages with user confirmation.

.PARAMETER ListOnly
    When set, only lists available updates without offering installation.
    Useful for auditing and reporting purposes.

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
#>

# ============================================================================
# Script Parameters
# ============================================================================
param(
    [switch]$AutoUpdate,  # Enable automatic update prompts
    [switch]$ListOnly     # List updates only, no installations
)

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
            } else {
                Write-ColorOutput -Message "Available updates found:" -Color "Yellow"
                # Display the list of available updates
                winget upgrade --include-unknown
                
                # If AutoUpdate is enabled and we're not in ListOnly mode, offer to install
                if ($AutoUpdate -and -not $ListOnly) {
                    $choice = Read-Host "`nDo you want to update all Winget packages? (Y/N)"
                    if ($choice -eq 'Y' -or $choice -eq 'y') {
                        # Upgrade all packages silently
                        winget upgrade --all --silent
                        Write-ColorOutput -Message "Winget packages updated successfully" -Color "Green"
                    }
                }
            }
        } catch {
            # Handle any errors during winget operations
            Write-ColorOutput -Message "Error checking Winget updates: $($_.Exception.Message)" -Color "Red"
        }
    } else {
        # Winget not found on the system
        Write-ColorOutput -Message "Winget is not available" -Color "Red"
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
    Write-ColorOutput -Message "`n=== Microsoft Store Apps ===" -Color "Cyan"
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-ColorOutput -Message "Skipping Store updates check - requires Administrator privileges" -Color "Yellow"
        Write-ColorOutput -Message "Run PowerShell as Administrator to check Microsoft Store updates" -Color "Yellow"
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
        
        # Note: Store apps require the Microsoft Store app for viewing/installing updates
        Write-ColorOutput -Message "Check the Microsoft Store app for available updates" -Color "Yellow"
    } catch [Microsoft.Management.Infrastructure.CimException] {
        # Handle CIM-specific errors (permission denied, namespace not found, etc.)
        if ($_.Exception.Message -like "*Access denied*" -or $_.Exception.HResult -eq 0x80041003) {
            Write-ColorOutput -Message "Access denied to Microsoft Store update service" -Color "Red"
            Write-ColorOutput -Message "Please run PowerShell as Administrator to check Store updates" -Color "Yellow"
        } elseif ($_.Exception.Message -like "*Invalid namespace*") {
            Write-ColorOutput -Message "Microsoft Store MDM namespace not available on this system" -Color "Yellow"
            Write-ColorOutput -Message "This feature may not be supported on your Windows edition" -Color "Yellow"
        } else {
            Write-ColorOutput -Message "Error checking Store updates: $($_.Exception.Message)" -Color "Red"
        }
    } catch {
        # Handle other unexpected errors
        Write-ColorOutput -Message "Unexpected error checking Store updates: $($_.Exception.Message)" -Color "Red"
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
    # Verify Chocolatey is installed and accessible
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-ColorOutput -Message "`n=== Chocolatey Packages ===" -Color "Cyan"
        
        try {
            # List all outdated Chocolatey packages
            # This command shows package name, current version, and available version
            choco outdated
        } catch {
            # Handle any errors during Chocolatey operations
            Write-ColorOutput -Message "Error checking Chocolatey updates: $($_.Exception.Message)" -Color "Red"
        }
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

# Execute all update checks in sequence
Check-WingetUpdates
Check-StoreUpdates
Check-ChocolateyUpdates
Get-InstalledSoftware

# Display completion message
Write-ColorOutput -Message ("`n" + ("=" * 60)) -Color "Magenta"
Write-ColorOutput -Message "Update check completed!" -Color "Green"

# Indicate mode of operation
if ($AutoUpdate) {
    Write-ColorOutput -Message "Auto-update mode was enabled" -Color "Yellow"
}
if ($ListOnly) {
    Write-ColorOutput -Message "List-only mode - no updates were installed" -Color "Cyan"
}
Write-ColorOutput -Message ("=" * 60) -Color "Magenta"