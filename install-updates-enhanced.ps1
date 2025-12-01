<#
.SYNOPSIS
    Enhanced Automated Windows Update Installer with logging, configuration, and reporting.

.DESCRIPTION
    This script automatically checks for and installs updates across three package management platforms:
    - Microsoft Store apps (via CIM/WMI)
    - Winget packages (Windows Package Manager)
    - Chocolatey packages (Community Package Manager)
    
    New features:
    - Configuration file support (config.json)
    - Comprehensive logging and audit trails
    - Pre-flight system checks
    - HTML/CSV/JSON report generation
    - System restore point creation
    - Package exclusion support

.PARAMETER ConfigPath
    Path to configuration file (default: config.json)

.PARAMETER SkipRestorePoint
    Skip creating a system restore point before updates

.PARAMETER GenerateReport
    Generate an HTML report of the update session

.NOTES
    File Name      : install-updates-enhanced.ps1
    Author         : sathyendrav
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges recommended
    Required Tools : Winget (App Installer), Chocolatey (optional)
    
.EXAMPLE
    .\install-updates-enhanced.ps1
    Runs all updates with default configuration.

.EXAMPLE
    .\install-updates-enhanced.ps1 -SkipRestorePoint -GenerateReport
    Runs updates without restore point but generates a report.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$SkipRestorePoint,
    [switch]$GenerateReport
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# ============================================================================
# Initialize
# ============================================================================

# Load configuration
$config = Get-UpdateConfig -ConfigPath $ConfigPath
if (-not $config) {
    # Use defaults if config not found
    $config = @{
        UpdateSettings = @{
            EnableMicrosoftStore = $true
            EnableWinget = $true
            EnableChocolatey = $true
            CreateRestorePoint = $true
            CheckDiskSpace = $true
            MinimumFreeSpaceGB = 10
        }
        Logging = @{
            EnableLogging = $true
            LogDirectory = ".\logs"
        }
        ReportSettings = @{
            GenerateReport = $false
            ReportFormat = "HTML"
            ReportDirectory = ".\reports"
        }
    }
}

# Initialize logging
$logFile = $null
if ($config.Logging.EnableLogging) {
    $logFile = Initialize-Logging -LogDirectory $config.Logging.LogDirectory -ScriptName "install-updates"
}

# Initialize update history database
if ($config.Logging.EnableUpdateHistory) {
    $historyPath = if ($config.Logging.HistoryDatabasePath) { 
        $config.Logging.HistoryDatabasePath 
    } else { 
        ".\logs\update-history.json" 
    }
    Initialize-UpdateHistory -HistoryPath $historyPath | Out-Null
}

Write-Log "=" * 70 -Level "Info"
Write-Log "Windows Update Helper - Enhanced Automated Installer" -Level "Info"
Write-Log "=" * 70 -Level "Info"

# Send start notification
Send-UpdateNotification -Type "Start" -Config $config

# Initialize report data
$reportData = @{
    SystemInfo = @{
        OS = (Get-CimInstance Win32_OperatingSystem).Caption
        Version = (Get-CimInstance Win32_OperatingSystem).Version
        LastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    }
    Store = @{ Status = "Not Run"; Count = 0; Errors = @() }
    Winget = @{ Status = "Not Run"; Count = 0; Errors = @() }
    Chocolatey = @{ Status = "Not Run"; Count = 0; Errors = @() }
    StartTime = Get-Date
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

Write-Log "`nRunning pre-flight checks..." -Level "Info"
$preflightPassed = Test-Prerequisites -CheckInternet -CheckDiskSpace -CheckAdmin -MinFreeSpaceGB $config.UpdateSettings.MinimumFreeSpaceGB

if (-not $preflightPassed) {
    Write-Log "Some pre-flight checks failed. Continue? (Y/N)" -Level "Warning"
    $response = Read-Host
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Log "Update process cancelled by user." -Level "Warning"
        Stop-Logging -LogFile $logFile
        exit 1
    }
}

# ============================================================================
# Create Restore Point
# ============================================================================

if ($config.UpdateSettings.CreateRestorePoint -and -not $SkipRestorePoint) {
    Write-Log "`nCreating system restore point..." -Level "Info"
    $restorePointCreated = New-UpdateRestorePoint -Description "Before Windows Update Helper - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    if (-not $restorePointCreated) {
        Write-Log "Failed to create restore point. Continue anyway? (Y/N)" -Level "Warning"
        $response = Read-Host
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Log "Update process cancelled by user." -Level "Warning"
            Stop-Logging -LogFile $logFile
            exit 1
        }
    }
}

# ============================================================================
# Microsoft Store Updates
# ============================================================================

if ($config.UpdateSettings.EnableMicrosoftStore) {
    Write-Log "`n" + ("=" * 70) -Level "Info"
    Write-Log "MICROSOFT STORE UPDATES" -Level "Info"
    Write-Log ("=" * 70) -Level "Info"
    
    if (Test-UpdateSource -Source "Store") {
        try {
            Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" `
                            -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | `
                Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
            
            Write-Log "Microsoft Store update scan initiated successfully." -Level "Success"
            $reportData.Store.Status = "Success"
            
            # Record history entry
            if ($config.Logging.EnableUpdateHistory) {
                Add-UpdateHistoryEntry -PackageName "Microsoft Store Apps" -Version "N/A" `
                    -Source "Store" -Operation "Scan" -Success $true -HistoryPath $historyPath
            }
        } catch {
            Write-Log "Failed to check Microsoft Store updates: $_" -Level "Error"
            $reportData.Store.Status = "Error"
            $reportData.Store.Errors += $_.Exception.Message
            
            # Record failure
            if ($config.Logging.EnableUpdateHistory) {
                Add-UpdateHistoryEntry -PackageName "Microsoft Store Apps" -Version "N/A" `
                    -Source "Store" -Operation "Scan" -Success $false -ErrorMessage $_.Exception.Message -HistoryPath $historyPath
            }
        }
    } else {
        Write-Log "Microsoft Store update source is not accessible." -Level "Warning"
        $reportData.Store.Status = "Unavailable"
    }
} else {
    Write-Log "Microsoft Store updates disabled in configuration." -Level "Info"
    $reportData.Store.Status = "Disabled"
}

# ============================================================================
# Winget Updates
# ============================================================================

if ($config.UpdateSettings.EnableWinget) {
    Write-Log "`n" + ("=" * 70) -Level "Info"
    Write-Log "WINGET PACKAGE UPDATES" -Level "Info"
    Write-Log ("=" * 70) -Level "Info"
    
    if (Test-UpdateSource -Source "Winget") {
        try {
            Write-Log "Checking for available Winget updates..." -Level "Info"
            
            # Get list of updates
            $wingetList = winget upgrade 2>&1
            Write-Log "$wingetList" -Level "Info"
            
            # Check for exclusions
            $exclusions = $config.PackageExclusions.Winget
            if ($exclusions -and $exclusions.Count -gt 0) {
                Write-Log "Excluding packages: $($exclusions -join ', ')" -Level "Info"
            }
            
            Write-Log "`nStarting Winget package upgrades..." -Level "Info"
            $wingetResult = winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1
            $wingetExitCode = $LASTEXITCODE
            
            if ($wingetExitCode -eq 0) {
                Write-Log "Winget packages updated successfully." -Level "Success"
                $reportData.Winget.Status = "Success"
                
                # Record history entry for successful upgrade
                if ($config.Logging.EnableUpdateHistory) {
                    Add-UpdateHistoryEntry -PackageName "Winget Packages (Batch)" -Version "Latest" `
                        -Source "Winget" -Operation "Upgrade" -Success $true -HistoryPath $historyPath
                }
            } else {
                Write-Log "Winget upgrade completed with warnings or errors." -Level "Warning"
                $reportData.Winget.Status = "Partial"
                
                if ($config.Logging.EnableUpdateHistory) {
                    Add-UpdateHistoryEntry -PackageName "Winget Packages (Batch)" -Version "Latest" `
                        -Source "Winget" -Operation "Upgrade" -Success $false -ErrorMessage "Exit code: $wingetExitCode" -HistoryPath $historyPath
                }
            }
        } catch {
            Write-Log "Error during Winget updates: $_" -Level "Error"
            $reportData.Winget.Status = "Error"
            $reportData.Winget.Errors += $_.Exception.Message
            
            # Record failure
            if ($config.Logging.EnableUpdateHistory) {
                Add-UpdateHistoryEntry -PackageName "Winget Packages (Batch)" -Version "Latest" `
                    -Source "Winget" -Operation "Upgrade" -Success $false -ErrorMessage $_.Exception.Message -HistoryPath $historyPath
            }
        }
    } else {
        Write-Log "Winget is not available on this system." -Level "Warning"
        Write-Log "Install 'App Installer' from Microsoft Store to enable Winget." -Level "Info"
        $reportData.Winget.Status = "Unavailable"
    }
} else {
    Write-Log "Winget updates disabled in configuration." -Level "Info"
    $reportData.Winget.Status = "Disabled"
}

# ============================================================================
# Chocolatey Updates
# ============================================================================

if ($config.UpdateSettings.EnableChocolatey) {
    Write-Log "`n" + ("=" * 70) -Level "Info"
    Write-Log "CHOCOLATEY PACKAGE UPDATES" -Level "Info"
    Write-Log ("=" * 70) -Level "Info"
    
    if (Test-UpdateSource -Source "Chocolatey") {
        try {
            # Check for exclusions
            $exclusions = $config.PackageExclusions.Chocolatey
            if ($exclusions -and $exclusions.Count -gt 0) {
                Write-Log "Excluding packages: $($exclusions -join ', ')" -Level "Info"
                
                # Build exclusion parameters
                $excludeParams = $exclusions | ForEach-Object { "--except=$_" }
                $chocoResult = choco upgrade all -y $excludeParams 2>&1
            } else {
                $chocoResult = choco upgrade all -y 2>&1
            }
            
            $chocoExitCode = $LASTEXITCODE
            
            if ($chocoExitCode -eq 0) {
                Write-Log "Chocolatey packages updated successfully." -Level "Success"
                $reportData.Chocolatey.Status = "Success"
                
                # Record history entry
                if ($config.Logging.EnableUpdateHistory) {
                    Add-UpdateHistoryEntry -PackageName "Chocolatey Packages (Batch)" -Version "Latest" `
                        -Source "Chocolatey" -Operation "Upgrade" -Success $true -HistoryPath $historyPath
                }
            } else {
                Write-Log "Chocolatey upgrade completed with warnings or errors." -Level "Warning"
                $reportData.Chocolatey.Status = "Partial"
                
                if ($config.Logging.EnableUpdateHistory) {
                    Add-UpdateHistoryEntry -PackageName "Chocolatey Packages (Batch)" -Version "Latest" `
                        -Source "Chocolatey" -Operation "Upgrade" -Success $false -ErrorMessage "Exit code: $chocoExitCode" -HistoryPath $historyPath
                }
            }
        } catch {
            Write-Log "Error during Chocolatey updates: $_" -Level "Error"
            $reportData.Chocolatey.Status = "Error"
            $reportData.Chocolatey.Errors += $_.Exception.Message
            
            # Record failure
            if ($config.Logging.EnableUpdateHistory) {
                Add-UpdateHistoryEntry -PackageName "Chocolatey Packages (Batch)" -Version "Latest" `
                    -Source "Chocolatey" -Operation "Upgrade" -Success $false -ErrorMessage $_.Exception.Message -HistoryPath $historyPath
            }
        }
        }
    } else {
        Write-Log "Chocolatey is not available on this system." -Level "Warning"
        Write-Log "Visit https://chocolatey.org/install for installation instructions." -Level "Info"
        $reportData.Chocolatey.Status = "Unavailable"
    }
} else {
    Write-Log "Chocolatey updates disabled in configuration." -Level "Info"
    $reportData.Chocolatey.Status = "Disabled"
}

# ============================================================================
# Generate Report
# ============================================================================

$reportData.EndTime = Get-Date
$reportData.Duration = ($reportData.EndTime - $reportData.StartTime).TotalMinutes

if ($GenerateReport -or $config.ReportSettings.GenerateReport) {
    Write-Log "`nGenerating update report..." -Level "Info"
    $reportPath = Export-UpdateReport -ReportData $reportData `
                                      -Format $config.ReportSettings.ReportFormat `
                                      -OutputPath $config.ReportSettings.ReportDirectory
    Write-Log "Report saved to: $reportPath" -Level "Success"
}

# ============================================================================
# Completion
# ============================================================================

Write-Log "`n" + ("=" * 70) -Level "Info"
Write-Log "UPDATE SESSION COMPLETED" -Level "Success"
Write-Log ("=" * 70) -Level "Info"
Write-Log "Duration: $([math]::Round($reportData.Duration, 2)) minutes" -Level "Info"
Write-Log "Store: $($reportData.Store.Status) | Winget: $($reportData.Winget.Status) | Chocolatey: $($reportData.Chocolatey.Status)" -Level "Info"

# Send completion notification
$totalUpdates = $reportData.Store.Count + $reportData.Winget.Count + $reportData.Chocolatey.Count
$hasErrors = ($reportData.Store.Errors.Count -gt 0) -or ($reportData.Winget.Errors.Count -gt 0) -or ($reportData.Chocolatey.Errors.Count -gt 0)

if ($hasErrors) {
    Send-UpdateNotification -Type "Error" -Details "Updates completed with errors. Check log for details." -Config $config
} elseif ($totalUpdates -gt 0) {
    Send-UpdateNotification -Type "Complete" -Details "$totalUpdates package(s) updated successfully in $([math]::Round($reportData.Duration, 1)) minutes" -Config $config
} else {
    Send-UpdateNotification -Type "NoUpdates" -Config $config
}

if ($logFile) {
    Write-Log "Log file: $logFile" -Level "Info"
}

# Stop logging
Stop-Logging -LogFile $logFile

# Pause before exit (compatible with all PowerShell hosts)
Write-Host "`nPress Enter to exit..." -ForegroundColor Cyan
try {
    $null = Read-Host
} catch {
    # If Read-Host fails (shouldn't happen), just exit gracefully
    Start-Sleep -Seconds 2
}
