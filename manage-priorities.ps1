<#
.SYNOPSIS
    Package Priority Manager - Configure update priorities interactively.

.DESCRIPTION
    Interactive menu-driven utility for managing package update priorities:
    - View current priority configuration
    - Add packages to priority levels
    - Remove packages from priorities
    - View priority statistics
    - Test priority ordering

.PARAMETER ConfigPath
    Path to configuration file (default: config.json)

.EXAMPLE
    .\manage-priorities.ps1
    Launch interactive priority management menu.

.NOTES
    File Name      : manage-priorities.ps1
    Author         : Sathyendra Vemulapalli
    Prerequisite   : PowerShell 5.1 or later
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# ============================================================================
# Helper Functions
# ============================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  Package Priority Manager" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. View Priority Configuration" -ForegroundColor White
    Write-Host "2. Add Package to Priority Level" -ForegroundColor White
    Write-Host "3. Remove Package from Priorities" -ForegroundColor White
    Write-Host "4. View Priority Statistics" -ForegroundColor White
    Write-Host "5. List Packages by Priority" -ForegroundColor White
    Write-Host "6. Test Priority Ordering" -ForegroundColor White
    Write-Host "7. Enable/Disable Priority Ordering" -ForegroundColor White
    Write-Host "8. Change Ordering Strategy" -ForegroundColor White
    Write-Host "9. Exit" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function View-PriorityConfiguration {
    $config = Get-UpdateConfig -ConfigPath $ConfigPath
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Current Priority Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    Write-Host "`nPriority Ordering: " -NoNewline -ForegroundColor White
    if ($config.PackagePriority.EnablePriorityOrdering) {
        Write-Host "ENABLED" -ForegroundColor Green
    } else {
        Write-Host "DISABLED" -ForegroundColor Red
    }
    
    Write-Host "Ordering Strategy: " -NoNewline -ForegroundColor White
    Write-Host $config.PackagePriority.OrderingStrategy -ForegroundColor Yellow
    
    # Show each priority level
    $priorities = @(
        @{Name="Critical"; Key="CriticalPackages"; Color="Red"},
        @{Name="High"; Key="HighPriorityPackages"; Color="Yellow"},
        @{Name="Low"; Key="LowPriorityPackages"; Color="Cyan"},
        @{Name="Deferred"; Key="DeferredPackages"; Color="Gray"}
    )
    
    foreach ($priority in $priorities) {
        Write-Host "`n$($priority.Name) Priority Packages:" -ForegroundColor $priority.Color
        Write-Host ("-" * 70) -ForegroundColor Gray
        
        $sources = @("Winget", "Chocolatey", "Store")
        foreach ($source in $sources) {
            $packages = @($config.PackagePriority.($priority.Key).$source)
            if ($packages.Count -gt 0) {
                Write-Host "  $source ($($packages.Count)):" -ForegroundColor White
                foreach ($pkg in $packages) {
                    Write-Host "    - $pkg" -ForegroundColor Gray
                }
            } else {
                Write-Host "  $source (0): None" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Add-PackageToPriorityMenu {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Add Package to Priority Level" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    # Get package name
    Write-Host "`nEnter package name/ID: " -NoNewline -ForegroundColor Yellow
    $packageName = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        Write-Host "Invalid package name" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Get source
    Write-Host "`nSelect source:" -ForegroundColor Yellow
    Write-Host "1. Winget" -ForegroundColor White
    Write-Host "2. Chocolatey" -ForegroundColor White
    Write-Host "3. Store" -ForegroundColor White
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    $sourceChoice = Read-Host
    
    $source = switch ($sourceChoice) {
        "1" { "Winget" }
        "2" { "Chocolatey" }
        "3" { "Store" }
        default { $null }
    }
    
    if (-not $source) {
        Write-Host "Invalid source selection" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Get priority
    Write-Host "`nSelect priority level:" -ForegroundColor Yellow
    Write-Host "1. Critical (highest priority)" -ForegroundColor Red
    Write-Host "2. High" -ForegroundColor Yellow
    Write-Host "3. Low" -ForegroundColor Cyan
    Write-Host "4. Deferred (lowest priority)" -ForegroundColor Gray
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    $priorityChoice = Read-Host
    
    $priority = switch ($priorityChoice) {
        "1" { "Critical" }
        "2" { "High" }
        "3" { "Low" }
        "4" { "Deferred" }
        default { $null }
    }
    
    if (-not $priority) {
        Write-Host "Invalid priority selection" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Add package
    Write-Host "`nAdding $packageName ($source) to $priority priority..." -ForegroundColor Yellow
    $success = Add-PackageToPriority -PackageName $packageName -Source $source -Priority $priority -ConfigPath $ConfigPath
    
    if ($success) {
        Write-Host "Successfully added package to priority list!" -ForegroundColor Green
    } else {
        Write-Host "Failed to add package (may already exist)" -ForegroundColor Red
    }
    
    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Remove-PackageFromPriorityMenu {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Remove Package from Priorities" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    # Get package name
    Write-Host "`nEnter package name/ID: " -NoNewline -ForegroundColor Yellow
    $packageName = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        Write-Host "Invalid package name" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Get source
    Write-Host "`nSelect source:" -ForegroundColor Yellow
    Write-Host "1. Winget" -ForegroundColor White
    Write-Host "2. Chocolatey" -ForegroundColor White
    Write-Host "3. Store" -ForegroundColor White
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    $sourceChoice = Read-Host
    
    $source = switch ($sourceChoice) {
        "1" { "Winget" }
        "2" { "Chocolatey" }
        "3" { "Store" }
        default { $null }
    }
    
    if (-not $source) {
        Write-Host "Invalid source selection" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Confirm removal
    Write-Host "`nAre you sure you want to remove $packageName from all priority levels? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        Write-Host "`nRemoving $packageName ($source) from priorities..." -ForegroundColor Yellow
        $success = Remove-PackageFromPriority -PackageName $packageName -Source $source -ConfigPath $ConfigPath
        
        if ($success) {
            Write-Host "Successfully removed package from priority lists!" -ForegroundColor Green
        } else {
            Write-Host "Package not found in priority lists" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Removal cancelled" -ForegroundColor Yellow
    }
    
    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function View-PriorityStatistics {
    $summary = Get-PrioritySummary
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Priority Statistics" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    Write-Host "`nPriority Ordering: " -NoNewline -ForegroundColor White
    if ($summary.Enabled) {
        Write-Host "ENABLED" -ForegroundColor Green
    } else {
        Write-Host "DISABLED" -ForegroundColor Red
    }
    
    Write-Host "Ordering Strategy: " -NoNewline -ForegroundColor White
    Write-Host $summary.Strategy -ForegroundColor Yellow
    
    Write-Host "`nPackages by Priority Level:" -ForegroundColor White
    Write-Host ("-" * 70) -ForegroundColor Gray
    
    $totalCritical = $summary.Critical.Winget + $summary.Critical.Chocolatey + $summary.Critical.Store
    $totalHigh = $summary.High.Winget + $summary.High.Chocolatey + $summary.High.Store
    $totalLow = $summary.Low.Winget + $summary.Low.Chocolatey + $summary.Low.Store
    $totalDeferred = $summary.Deferred.Winget + $summary.Deferred.Chocolatey + $summary.Deferred.Store
    
    Write-Host "`nCritical: $totalCritical packages" -ForegroundColor Red
    Write-Host "  Winget: $($summary.Critical.Winget) | Chocolatey: $($summary.Critical.Chocolatey) | Store: $($summary.Critical.Store)" -ForegroundColor Gray
    
    Write-Host "`nHigh: $totalHigh packages" -ForegroundColor Yellow
    Write-Host "  Winget: $($summary.High.Winget) | Chocolatey: $($summary.High.Chocolatey) | Store: $($summary.High.Store)" -ForegroundColor Gray
    
    Write-Host "`nLow: $totalLow packages" -ForegroundColor Cyan
    Write-Host "  Winget: $($summary.Low.Winget) | Chocolatey: $($summary.Low.Chocolatey) | Store: $($summary.Low.Store)" -ForegroundColor Gray
    
    Write-Host "`nDeferred: $totalDeferred packages" -ForegroundColor DarkGray
    Write-Host "  Winget: $($summary.Deferred.Winget) | Chocolatey: $($summary.Deferred.Chocolatey) | Store: $($summary.Deferred.Store)" -ForegroundColor Gray
    
    $total = $totalCritical + $totalHigh + $totalLow + $totalDeferred
    Write-Host "`nTotal Priority Packages: $total" -ForegroundColor Green
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Test-PriorityOrdering {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Test Priority Ordering" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    Write-Host "`nSelect source to test:" -ForegroundColor Yellow
    Write-Host "1. Winget" -ForegroundColor White
    Write-Host "2. Chocolatey" -ForegroundColor White
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    $sourceChoice = Read-Host
    
    $source = switch ($sourceChoice) {
        "1" { "Winget" }
        "2" { "Chocolatey" }
        default { $null }
    }
    
    if (-not $source) {
        Write-Host "Invalid source selection" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    # Create test packages
    $testPackages = @(
        [PSCustomObject]@{Name="Package-A"},
        [PSCustomObject]@{Name="Package-B"},
        [PSCustomObject]@{Name="Package-C"}
    )
    
    $config = Get-UpdateConfig -ConfigPath $ConfigPath
    
    # Add configured packages
    $allPackages = @()
    $allPackages += @($config.PackagePriority.CriticalPackages.$source | ForEach-Object { [PSCustomObject]@{Name=$_} })
    $allPackages += @($config.PackagePriority.HighPriorityPackages.$source | ForEach-Object { [PSCustomObject]@{Name=$_} })
    $allPackages += $testPackages
    $allPackages += @($config.PackagePriority.LowPriorityPackages.$source | ForEach-Object { [PSCustomObject]@{Name=$_} })
    $allPackages += @($config.PackagePriority.DeferredPackages.$source | ForEach-Object { [PSCustomObject]@{Name=$_} })
    
    Write-Host "`nSorting packages..." -ForegroundColor Yellow
    $sorted = Sort-PackagesByPriority -Packages $allPackages -Source $source -Config $config
    
    Write-Host "`nSorted Package Order:" -ForegroundColor Cyan
    Write-Host ("-" * 70) -ForegroundColor Gray
    
    $position = 1
    foreach ($pkg in $sorted) {
        $priorityColor = switch ($pkg.Priority) {
            "Critical" { "Red" }
            "High" { "Yellow" }
            "Normal" { "White" }
            "Low" { "Cyan" }
            "Deferred" { "Gray" }
            default { "White" }
        }
        
        Write-Host "$position. " -NoNewline -ForegroundColor Gray
        Write-Host "$($pkg.Name) " -NoNewline -ForegroundColor White
        Write-Host "[$($pkg.Priority)]" -ForegroundColor $priorityColor
        $position++
    }
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Toggle-PriorityOrdering {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    $currentState = $config.PackagePriority.EnablePriorityOrdering
    $newState = -not $currentState
    
    $config.PackagePriority.EnablePriorityOrdering = $newState
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    if ($newState) {
        Write-Host "Priority Ordering ENABLED" -ForegroundColor Green
    } else {
        Write-Host "Priority Ordering DISABLED" -ForegroundColor Red
    }
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Change-OrderingStrategy {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "Change Ordering Strategy" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    Write-Host "`nSelect strategy:" -ForegroundColor Yellow
    Write-Host "1. PriorityOnly - Sort by priority level only" -ForegroundColor White
    Write-Host "2. PriorityThenAlphabetical - Priority, then A-Z" -ForegroundColor White
    Write-Host "3. PriorityThenReverseAlphabetical - Priority, then Z-A" -ForegroundColor White
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host
    
    $strategy = switch ($choice) {
        "1" { "PriorityOnly" }
        "2" { "PriorityThenAlphabetical" }
        "3" { "PriorityThenReverseAlphabetical" }
        default { $null }
    }
    
    if ($strategy) {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $config.PackagePriority.OrderingStrategy = $strategy
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
        
        Write-Host "`nOrdering strategy updated to: $strategy" -ForegroundColor Green
    } else {
        Write-Host "`nInvalid selection" -ForegroundColor Red
    }
    
    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ============================================================================
# Main Menu Loop
# ============================================================================

do {
    Show-MainMenu
    Write-Host "Select an option (1-9): " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host
    
    switch ($choice) {
        "1" { View-PriorityConfiguration }
        "2" { Add-PackageToPriorityMenu }
        "3" { Remove-PackageFromPriorityMenu }
        "4" { View-PriorityStatistics }
        "5" { View-PriorityConfiguration }  # Same as option 1
        "6" { Test-PriorityOrdering }
        "7" { Toggle-PriorityOrdering }
        "8" { Change-OrderingStrategy }
        "9" { 
            Write-Host "`nExiting..." -ForegroundColor Yellow
            break 
        }
        default {
            Write-Host "`nInvalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "9")

Write-Host "`nPackage Priority Manager closed." -ForegroundColor Cyan
