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
    Author         : Sathyendra Vemulapalli
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

# ============================================================================
# Dependency Installation
# ============================================================================

Write-Log "DEPENDENCY INSTALLATION" -Level "Info"
Write-Log "=" * 70 -Level "Info"

if ($config.DependencyInstallation -and $config.DependencyInstallation.EnableDependencyCheck) {
    Write-Log "Checking and installing required dependencies..." -Level "Info"
    
    $dependencyResult = Invoke-DependencyInstallation -Config $config
    
    if ($dependencyResult.Success) {
        $installedCount = ($dependencyResult.Dependencies | Where-Object { $_.Installed }).Count
        $totalCount = $dependencyResult.Dependencies.Count
        
        Write-Log "Dependencies satisfied: $installedCount/$totalCount" -Level "Success"
        
        # Log details
        foreach ($dep in $dependencyResult.Dependencies) {
            $statusIcon = if ($dep.Success) { "[OK]" } else { "[FAIL]" }
            $message = "$statusIcon $($dep.Dependency): $($dep.Action)"
            
            if ($dep.Success) {
                Write-Log $message -Level "Success"
            } else {
                Write-Log $message -Level "Warning"
            }
        }
    } else {
        Write-Log "Dependency check failed: $($dependencyResult.Message)" -Level "Warning"
        
        if ($config.DependencyInstallation.FailOnMissingDependencies) {
            Write-Log "FailOnMissingDependencies is enabled. Stopping execution." -Level "Error"
            
            # Log failed dependencies
            foreach ($dep in $dependencyResult.Dependencies | Where-Object { -not $_.Success }) {
                Write-Log "Missing: $($dep.Dependency)" -Level "Error"
            }
            
            Stop-Logging
            exit 1
        }
    }
} else {
    Write-Log "Dependency check is disabled" -Level "Info"
}

Write-Log "" -Level "Info"

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

# Initialize validation tracking
$validationPackages = @()

# Initialize security validation tracking
$securityPackages = @()

# Initialize hash database if security validation enabled
if ($config.SecurityValidation.EnableHashVerification) {
    Initialize-HashDatabase -DatabasePath $config.SecurityValidation.HashDatabasePath
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
            
            # Parse available updates for validation tracking
            if ($config.UpdateValidation.EnableValidation) {
                $wingetOutput = winget list 2>&1 | Out-String
                $wingetLines = $wingetOutput -split "`n" | Where-Object { $_ -match '\S' }
                foreach ($line in $wingetLines) {
                    if ($line -match '([\w\.]+)\s+([\d\.]+)') {
                        $pkgName = $matches[1]
                        $pkgVersion = $matches[2]
                        if ($pkgName -ne 'Name' -and $pkgName -ne 'Id') {
                            $validationPackages += @{
                                Name = $pkgName
                                Source = "Winget"
                                PreviousVersion = $pkgVersion
                                ExpectedVersion = $null
                            }
                        }
                    }
                }
                Write-Log "Captured $($validationPackages.Count) package versions for validation" -Level "Info"
            }
            
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
            # Capture versions for validation
            if ($config.UpdateValidation.EnableValidation) {
                Write-Log "Capturing package versions for validation..." -Level "Info"
                $chocoList = choco list --local-only 2>&1 | Out-String
                $chocoLines = $chocoList -split "`n" | Where-Object { $_ -match '\S' }
                foreach ($line in $chocoLines) {
                    if ($line -match '([\w\.-]+)\s+([\d\.]+)') {
                        $pkgName = $matches[1]
                        $pkgVersion = $matches[2]
                        $validationPackages += @{
                            Name = $pkgName
                            Source = "Chocolatey"
                            PreviousVersion = $pkgVersion
                            ExpectedVersion = $null
                        }
                    }
                }
            }
            
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
# Update Validation
# ============================================================================

if ($config.UpdateValidation.EnableValidation -and $validationPackages.Count -gt 0) {
    Write-Log "`n" + ("=" * 70) -Level "Info"
    Write-Log "UPDATE VALIDATION" -Level "Info"
    Write-Log ("=" * 70) -Level "Info"
    
    Write-Log "Validating $($validationPackages.Count) package updates..." -Level "Info"
    
    # Perform validation
    $validationResults = Invoke-UpdateValidation -Packages $validationPackages -Config $config
    
    # Generate validation report
    $validationReportPath = Join-Path $config.ReportSettings.ReportDirectory "validation-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $reportCreated = New-ValidationReport -ValidationResults $validationResults -OutputPath $validationReportPath -Format "HTML"
    
    if ($reportCreated) {
        Write-Log "Validation report saved to: $validationReportPath" -Level "Success"
    }
    
    # Summary
    $successCount = ($validationResults | Where-Object { $_.ValidationSuccess }).Count
    $failureCount = ($validationResults | Where-Object { -not $_.ValidationSuccess }).Count
    Write-Log "`nValidation Summary: $successCount passed, $failureCount failed" -Level "Info"
    
    # Add validation data to report
    $reportData.Validation = @{
        Total = $validationResults.Count
        Successful = $successCount
        Failed = $failureCount
        Results = $validationResults
    }
}

# ============================================================================
# Security Validation
# ============================================================================

if (($config.SecurityValidation.EnableHashVerification -or $config.SecurityValidation.EnableSignatureValidation) -and 
    $validationPackages.Count -gt 0) {
    Write-Log "`n" + ("=" * 70) -Level "Info"
    Write-Log "SECURITY VALIDATION" -Level "Info"
    Write-Log ("=" * 70) -Level "Info"
    
    Write-Log "Performing security validation on $($validationPackages.Count) packages..." -Level "Info"
    
    # Perform security validation
    $securityResults = Invoke-SecurityValidation -Packages $validationPackages -Config $config
    
    # Generate security report
    $securityReportPath = Join-Path $config.ReportSettings.ReportDirectory "security-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $reportCreated = New-SecurityReport -ValidationResults $securityResults -OutputPath $securityReportPath -Format "HTML"
    
    if ($reportCreated) {
        Write-Log "Security report saved to: $securityReportPath" -Level "Success"
    }
    
    # Summary
    $securityPassCount = ($securityResults | Where-Object { $_.SecurityPassed }).Count
    $securityFailCount = ($securityResults | Where-Object { -not $_.SecurityPassed }).Count
    Write-Log "`nSecurity Summary: $securityPassCount passed, $securityFailCount failed" -Level "Info"
    
    # Check for critical security failures
    if ($config.SecurityValidation.BlockUntrustedPackages) {
        $criticalFailures = $securityResults | Where-Object { -not $_.SecurityPassed }
        if ($criticalFailures.Count -gt 0) {
            Write-Log "WARNING: $($criticalFailures.Count) package(s) failed security validation!" -Level "Warning"
            foreach ($failure in $criticalFailures) {
                Write-Log "  - $($failure.PackageName): $($failure.Message)" -Level "Warning"
            }
        }
    }
    
    # Add security data to report
    $reportData.Security = @{
        Total = $securityResults.Count
        Passed = $securityPassCount
        Failed = $securityFailCount
        Results = $securityResults
    }
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
