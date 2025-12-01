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
    Author         : Sathyendra Vemulapalli
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

# Send start notification
Send-UpdateNotification -Type "Start" -Config $config

# Initialize cache if differential updates enabled
$useDifferentialUpdates = $config -and $config.DifferentialUpdates.EnableDifferentialUpdates
if ($useDifferentialUpdates) {
    Write-Log "Differential updates enabled - will compare with cached versions" -Level "Info"
    $cachePath = if ($config.DifferentialUpdates.CachePath) { 
        Join-Path $PSScriptRoot $config.DifferentialUpdates.CachePath.TrimStart(".\")
    } else { 
        "$PSScriptRoot\cache\package-cache.json" 
    }
    Initialize-PackageCache -CachePath $cachePath
}

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
        $wingetOutput = winget upgrade --include-unknown 2>&1
        
        if ($useDifferentialUpdates) {
            # Parse winget output to get package list
            $wingetPackages = @()
            $lines = $wingetOutput | Where-Object { $_ -match '\S' }
            $inPackageList = $false
            
            foreach ($line in $lines) {
                if ($line -match '^Name\s+Id\s+Version\s+Available') {
                    $inPackageList = $true
                    continue
                }
                if ($inPackageList -and $line -match '^\-+') {
                    continue
                }
                if ($inPackageList -and $line -match '^\s*$') {
                    break
                }
                if ($inPackageList) {
                    # Parse package line
                    if ($line -match '^\s*(.+?)\s{2,}(\S+)\s+(\S+)\s+(\S+)') {
                        $wingetPackages += @{
                            Name = $matches[1].Trim()
                            Id = $matches[2].Trim()
                            Version = $matches[3].Trim()
                            Available = $matches[4].Trim()
                        }
                    }
                }
            }
            
            # Compare with cache
            if ($wingetPackages.Count -gt 0) {
                $changedPackages = Compare-PackageVersions -CurrentPackages $wingetPackages -Source "Winget" -CachePath $cachePath
                
                if ($changedPackages.Count -gt 0) {
                    Write-Log "Found $($changedPackages.Count) new or updated Winget packages (differential mode):" -Level "Info"
                    foreach ($pkg in $changedPackages) {
                        $changeInfo = if ($pkg.ChangeType -eq "New") {
                            "NEW"
                        } else {
                            "$($pkg.PreviousVersion) -> $($pkg.Available)"
                        }
                        Write-Log "  - $($pkg.Name) [$changeInfo]" -Level "Info"
                    }
                } else {
                    Write-Log "No new Winget updates since last check" -Level "Success"
                }
                
                # Update cache if configured
                if ($config.DifferentialUpdates.AlwaysUpdateCache) {
                    foreach ($pkg in $wingetPackages) {
                        Update-PackageCache -PackageName $pkg.Id -Version $pkg.Available -Source "Winget" -CachePath $cachePath
                    }
                }
            }
        } else {
            # Standard mode - show all output
            $wingetOutput | ForEach-Object { Write-Log $_ -Level "Info" }
        }
        
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
        $chocoOutput = choco outdated 2>&1
        
        if ($useDifferentialUpdates) {
            # Parse chocolatey output
            $chocoPackages = @()
            $lines = $chocoOutput | Where-Object { $_ -match '\S' }
            
            foreach ($line in $lines) {
                # Parse format: PackageName|CurrentVersion|AvailableVersion|Pinned
                if ($line -match '^([^|]+)\|([^|]+)\|([^|]+)') {
                    $chocoPackages += @{
                        Name = $matches[1].Trim()
                        Version = $matches[2].Trim()
                        Available = $matches[3].Trim()
                    }
                }
            }
            
            # Compare with cache
            if ($chocoPackages.Count -gt 0) {
                $changedPackages = Compare-PackageVersions -CurrentPackages $chocoPackages -Source "Chocolatey" -CachePath $cachePath
                
                if ($changedPackages.Count -gt 0) {
                    Write-Log "Found $($changedPackages.Count) new or updated Chocolatey packages (differential mode):" -Level "Info"
                    foreach ($pkg in $changedPackages) {
                        $changeInfo = if ($pkg.ChangeType -eq "New") {
                            "NEW"
                        } else {
                            "$($pkg.PreviousVersion) -> $($pkg.Available)"
                        }
                        Write-Log "  - $($pkg.Name) [$changeInfo]" -Level "Info"
                    }
                } else {
                    Write-Log "No new Chocolatey updates since last check" -Level "Success"
                }
                
                # Update cache if configured
                if ($config.DifferentialUpdates.AlwaysUpdateCache) {
                    foreach ($pkg in $chocoPackages) {
                        Update-PackageCache -PackageName $pkg.Name -Version $pkg.Available -Source "Chocolatey" -CachePath $cachePath
                    }
                }
            }
        } else {
            # Standard mode - show all output
            $chocoOutput | ForEach-Object { Write-Log $_ -Level "Info" }
        }
        
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

if ($useDifferentialUpdates) {
    $cacheStats = Get-CacheStatistics -CachePath $cachePath
    Write-Log "Cache status: $($cacheStats.TotalPackages) packages cached, last updated $($cacheStats.LastUpdated)" -Level "Info"
} else {
    Write-Log "No packages were installed - this was a preview only." -Level "Info"
}

Write-Log ("=" * 70) -Level "Info"

# Send completion notification
Send-UpdateNotification -Type "UpdatesFound" -Details "Update scan completed. Check console for details." -Config $config

if ($logFile) {
    Write-Log "Log file: $logFile" -Level "Info"
}

# Stop logging
Stop-Logging -LogFile $logFile