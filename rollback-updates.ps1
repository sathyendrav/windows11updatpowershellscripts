<#
.SYNOPSIS
    Rollback and restore utility for Windows updates.

.DESCRIPTION
    This script provides rollback capabilities for Windows updates:
    - List and restore to system restore points
    - View package update history
    - Rollback specific packages to previous versions
    - Interactive menu-driven interface

.PARAMETER ListRestorePoints
    List all available system restore points.

.PARAMETER RestorePointNumber
    Restore system to specific restore point sequence number.

.PARAMETER ListHistory
    Show package update history.

.PARAMETER RollbackPackage
    Package name to rollback.

.PARAMETER Version
    Target version for package rollback.

.PARAMETER Source
    Package source: Winget or Chocolatey.

.NOTES
    File Name      : rollback-updates.ps1
    Author         : sathyendrav
    Prerequisite   : PowerShell 5.1 or later, Administrator privileges
    
.EXAMPLE
    .\rollback-updates.ps1
    Launch interactive menu.

.EXAMPLE
    .\rollback-updates.ps1 -ListRestorePoints
    Display all system restore points.

.EXAMPLE
    .\rollback-updates.ps1 -RollbackPackage "googlechrome" -Version "119.0.6045.159" -Source Chocolatey
    Rollback Chrome to specific version using Chocolatey.
#>

[CmdletBinding()]
param(
    [switch]$ListRestorePoints,
    [int]$RestorePointNumber,
    [switch]$ListHistory,
    [string]$RollbackPackage,
    [string]$Version,
    [ValidateSet("Winget", "Chocolatey")]
    [string]$Source
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# ============================================================================
# Helper Functions
# ============================================================================

function Show-Menu {
    Clear-Host
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "  Windows Update Rollback & Restore Utility" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. List System Restore Points" -ForegroundColor White
    Write-Host "  2. Restore to a Restore Point" -ForegroundColor White
    Write-Host "  3. View Package Update History" -ForegroundColor White
    Write-Host "  4. Rollback a Package" -ForegroundColor White
    Write-Host "  5. Exit" -ForegroundColor White
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
}

function Show-RestorePoints {
    Write-Host "`nSystem Restore Points:" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Gray
    
    $restorePoints = Get-SystemRestorePoints
    
    if ($restorePoints) {
        $restorePoints | Format-Table -AutoSize `
            @{Label="Sequence"; Expression={$_.SequenceNumber}; Width=10},
            @{Label="Created"; Expression={$_.CreationTime.ToString("yyyy-MM-dd HH:mm")}; Width=18},
            @{Label="Description"; Expression={$_.Description}; Width=40},
            @{Label="Type"; Expression={$_.RestorePointType}; Width=15}
        
        Write-Host "Total restore points: $($restorePoints.Count)" -ForegroundColor Green
    } else {
        Write-Host "No restore points found or unable to retrieve them." -ForegroundColor Yellow
        Write-Host "Ensure you have administrator privileges." -ForegroundColor Yellow
    }
}

function Restore-ToPoint {
    Write-Host "`nRestore System to Previous State" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Gray
    
    $restorePoints = Get-SystemRestorePoints
    
    if (-not $restorePoints) {
        Write-Host "No restore points available." -ForegroundColor Red
        return
    }
    
    # Show available restore points
    $restorePoints | Format-Table -AutoSize `
        SequenceNumber,
        @{Label="Created"; Expression={$_.CreationTime.ToString("yyyy-MM-dd HH:mm")}},
        Description
    
    Write-Host ""
    $sequenceNum = Read-Host "Enter the Sequence Number to restore to (or 0 to cancel)"
    
    if ($sequenceNum -eq "0") {
        Write-Host "Restore cancelled." -ForegroundColor Yellow
        return
    }
    
    if ($sequenceNum -match '^\d+$') {
        $success = Invoke-SystemRestore -SequenceNumber ([int]$sequenceNum) -Confirm
        
        if (-not $success) {
            Write-Host "Restore failed or was cancelled." -ForegroundColor Red
        }
    } else {
        Write-Host "Invalid sequence number." -ForegroundColor Red
    }
}

function Show-PackageHistory {
    Write-Host "`nPackage Update History (Last 30 days):" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Gray
    
    Write-Host "`nRetrieving package history from database..." -ForegroundColor Yellow
    
    # Try to load from history database first
    $history = Get-UpdateHistory -Days 30
    
    if ($history -and $history.Count -gt 0) {
        Write-Host "`nFrom Update History Database:" -ForegroundColor Green
        $history | Format-Table -AutoSize `
            @{Label="Time"; Expression={$_.Timestamp}; Width=20},
            @{Label="Package"; Expression={$_.PackageName}; Width=30},
            @{Label="Version"; Expression={$_.Version}; Width=12},
            @{Label="Previous"; Expression={$_.PreviousVersion}; Width=12},
            @{Label="Source"; Expression={$_.Source}; Width=10},
            @{Label="Operation"; Expression={$_.Operation}; Width=10},
            @{Label="Status"; Expression={if ($_.Success) {"Success"} else {"Failed"}}; Width=8}
        
        Write-Host "Total entries: $($history.Count)" -ForegroundColor Green
    } else {
        Write-Host "No update history found in database." -ForegroundColor Yellow
        Write-Host "Attempting to extract from package manager logs..." -ForegroundColor Yellow
        
        # Fall back to old method
        $legacyHistory = Get-PackageHistory -Source All -Days 30
        
        if ($legacyHistory -and $legacyHistory.Count -gt 0) {
            $legacyHistory | Format-Table -AutoSize Source, Package, Version, Operation, Timestamp
            Write-Host "Total operations found: $($legacyHistory.Count)" -ForegroundColor Green
        } else {
            Write-Host "No recent package history found." -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nNote: For detailed history, check:" -ForegroundColor Gray
    Write-Host "  - Update history database: .\logs\update-history.json" -ForegroundColor Gray
    Write-Host "  - Winget logs: $env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir" -ForegroundColor Gray
    Write-Host "  - Chocolatey logs: $env:ChocolateyInstall\logs\chocolatey.log" -ForegroundColor Gray
}

function Rollback-Package {
    Write-Host "`nPackage Rollback" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Gray
    
    Write-Host "`nSelect package source:" -ForegroundColor Yellow
    Write-Host "  1. Winget" -ForegroundColor White
    Write-Host "  2. Chocolatey" -ForegroundColor White
    $sourceChoice = Read-Host "Enter choice (1 or 2)"
    
    $selectedSource = switch ($sourceChoice) {
        "1" { "Winget" }
        "2" { "Chocolatey" }
        default { 
            Write-Host "Invalid choice." -ForegroundColor Red
            return
        }
    }
    
    Write-Host ""
    $packageName = Read-Host "Enter package name/ID"
    $targetVersion = Read-Host "Enter target version"
    
    Write-Host ""
    Write-Host "WARNING: Rollback will:" -ForegroundColor Yellow
    if ($selectedSource -eq "Winget") {
        Write-Host "  1. Uninstall the current version" -ForegroundColor Yellow
        Write-Host "  2. Install the specified version" -ForegroundColor Yellow
        Write-Host "  Note: Not all Winget packages support version selection" -ForegroundColor Yellow
    } else {
        Write-Host "  1. Downgrade to the specified version using --allow-downgrade" -ForegroundColor Yellow
    }
    Write-Host ""
    
    $confirm = Read-Host "Continue with rollback? (Y/N)"
    
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        $success = Invoke-PackageRollback -PackageName $packageName -Version $targetVersion -Source $selectedSource
        
        if ($success) {
            Write-Host "`nRollback completed successfully!" -ForegroundColor Green
            
            # Record rollback in history
            Add-UpdateHistoryEntry -PackageName $packageName -Version $targetVersion `
                -Source $selectedSource -Operation "Rollback" -Success $true | Out-Null
        } else {
            Write-Host "`nRollback failed. Check error messages above." -ForegroundColor Red
            
            # Record failed rollback
            Add-UpdateHistoryEntry -PackageName $packageName -Version $targetVersion `
                -Source $selectedSource -Operation "Rollback" -Success $false -ErrorMessage "Rollback operation failed" | Out-Null
        }
    } else {
        Write-Host "Rollback cancelled." -ForegroundColor Yellow
    }
}

# ============================================================================
# Main Execution
# ============================================================================

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`nWARNING: Not running as Administrator" -ForegroundColor Yellow
    Write-Host "Some features (system restore) require administrator privileges." -ForegroundColor Yellow
    Write-Host "Right-click PowerShell and select 'Run as Administrator' for full functionality.`n" -ForegroundColor Yellow
}

# Handle command-line parameters
if ($ListRestorePoints) {
    Show-RestorePoints
    exit 0
}

if ($RestorePointNumber -gt 0) {
    $success = Invoke-SystemRestore -SequenceNumber $RestorePointNumber -Confirm
    exit $(if ($success) { 0 } else { 1 })
}

if ($ListHistory) {
    Show-PackageHistory
    exit 0
}

if ($RollbackPackage -and $Version -and $Source) {
    $success = Invoke-PackageRollback -PackageName $RollbackPackage -Version $Version -Source $Source
    exit $(if ($success) { 0 } else { 1 })
}

# Interactive menu mode
do {
    Show-Menu
    $choice = Read-Host "Select an option (1-5)"
    
    switch ($choice) {
        "1" {
            Show-RestorePoints
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            $null = Read-Host
        }
        "2" {
            if (-not $isAdmin) {
                Write-Host "`nERROR: System restore requires Administrator privileges." -ForegroundColor Red
                Write-Host "Please restart PowerShell as Administrator." -ForegroundColor Yellow
            } else {
                Restore-ToPoint
            }
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            $null = Read-Host
        }
        "3" {
            Show-PackageHistory
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            $null = Read-Host
        }
        "4" {
            Rollback-Package
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            $null = Read-Host
        }
        "5" {
            Write-Host "`nExiting..." -ForegroundColor Green
            break
        }
        default {
            Write-Host "`nInvalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne "5")
