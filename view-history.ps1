<#
.SYNOPSIS
    View and analyze update history database.

.DESCRIPTION
    This script provides tools to view, filter, and export update history
    from the JSON database. Supports various filters and export formats.

.PARAMETER Days
    Number of days of history to display (default: 30).

.PARAMETER Source
    Filter by package source: Store, Winget, or Chocolatey.

.PARAMETER PackageName
    Filter by package name (supports wildcards).

.PARAMETER FailedOnly
    Show only failed operations.

.PARAMETER Export
    Export history to HTML or CSV report.

.PARAMETER OutputPath
    Path for exported report.

.NOTES
    File Name      : view-history.ps1
    Author         : sathyendrav
    Prerequisite   : PowerShell 5.1 or later
    
.EXAMPLE
    .\view-history.ps1
    Display last 30 days of history.

.EXAMPLE
    .\view-history.ps1 -Days 7 -FailedOnly
    Show only failed operations from last 7 days.

.EXAMPLE
    .\view-history.ps1 -PackageName "*chrome*"
    Show all history entries for packages containing "chrome".

.EXAMPLE
    .\view-history.ps1 -Export HTML -OutputPath ".\reports\history.html"
    Export full history to HTML report.
#>

[CmdletBinding()]
param(
    [int]$Days = 30,
    
    [ValidateSet("Store", "Winget", "Chocolatey")]
    [string]$Source,
    
    [string]$PackageName,
    
    [switch]$FailedOnly,
    
    [ValidateSet("HTML", "CSV")]
    [string]$Export,
    
    [string]$OutputPath
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# ============================================================================
# Main Execution
# ============================================================================

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  Update History Viewer" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

# Build filter parameters
$filterParams = @{ Days = $Days }

if ($Source) {
    $filterParams.Source = $Source
}

if ($PackageName) {
    $filterParams.PackageName = $PackageName
}

if ($FailedOnly) {
    $filterParams.Success = $false
}

# Get history
Write-Host "`nRetrieving update history..." -ForegroundColor Yellow
$history = Get-UpdateHistory @filterParams

if (-not $history -or $history.Count -eq 0) {
    Write-Host "`nNo update history found matching the criteria." -ForegroundColor Yellow
    Write-Host "`nTips:" -ForegroundColor Gray
    Write-Host "  - Make sure update scripts have been run at least once" -ForegroundColor Gray
    Write-Host "  - Check that EnableUpdateHistory is true in config.json" -ForegroundColor Gray
    Write-Host "  - Try increasing the -Days parameter" -ForegroundColor Gray
    exit 0
}

# Display summary
Write-Host "`nUpdate History Summary:" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Gray
Write-Host "Period: Last $Days days" -ForegroundColor White

# Ensure history is always an array
$historyArray = @($history)
$successCount = @($history | Where-Object { $_.Success }).Count
$failCount = @($history | Where-Object { -not $_.Success }).Count

Write-Host "Total Entries: $($historyArray.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

# Group by source
$bySource = $history | Group-Object Source
Write-Host "`nBy Source:" -ForegroundColor Cyan
foreach ($group in $bySource) {
    Write-Host "  $($group.Name): $($group.Count) operations" -ForegroundColor White
}

# Group by operation
$byOperation = $history | Group-Object Operation
Write-Host "`nBy Operation:" -ForegroundColor Cyan
foreach ($group in $byOperation) {
    Write-Host "  $($group.Name): $($group.Count) operations" -ForegroundColor White
}

# Display detailed entries
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "Detailed History (sorted by most recent):" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

$history | Sort-Object Timestamp -Descending | Format-Table -AutoSize `
    @{Label="Time"; Expression={$_.Timestamp}; Width=20},
    @{Label="Package"; Expression={$_.PackageName}; Width=30},
    @{Label="Version"; Expression={$_.Version}; Width=12},
    @{Label="Source"; Expression={$_.Source}; Width=10},
    @{Label="Operation"; Expression={$_.Operation}; Width=10},
    @{Label="Status"; Expression={if ($_.Success) {"Success"} else {"Failed"}}; Width=10}

# Show recent failures with details
$recentFailures = $history | Where-Object { -not $_.Success } | Sort-Object Timestamp -Descending | Select-Object -First 5

if ($recentFailures) {
    Write-Host "`nRecent Failures (Details):" -ForegroundColor Red
    Write-Host ("=" * 70) -ForegroundColor Gray
    
    foreach ($failure in $recentFailures) {
        Write-Host "`n[$($failure.Timestamp)] $($failure.PackageName)" -ForegroundColor Yellow
        Write-Host "  Source: $($failure.Source)" -ForegroundColor Gray
        Write-Host "  Operation: $($failure.Operation)" -ForegroundColor Gray
        Write-Host "  Error: $($failure.ErrorMessage)" -ForegroundColor Red
    }
}

# Export if requested
if ($Export -and $OutputPath) {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Exporting history..." -ForegroundColor Yellow
    
    $exportSuccess = Export-UpdateHistoryReport -Format $Export -OutputPath $OutputPath -Days $Days
    
    if ($exportSuccess) {
        Write-Host "History exported successfully to: $OutputPath" -ForegroundColor Green
        
        # Open the file if HTML
        if ($Export -eq "HTML") {
            $openFile = Read-Host "`nOpen the report in browser? (Y/N)"
            if ($openFile -eq 'Y' -or $openFile -eq 'y') {
                Start-Process $OutputPath
            }
        }
    } else {
        Write-Host "Failed to export history report" -ForegroundColor Red
    }
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "History database location: .\logs\update-history.json" -ForegroundColor Gray
Write-Host ("=" * 70) -ForegroundColor Cyan
