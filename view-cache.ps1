<#
.SYNOPSIS
    Package Cache Viewer - Displays cached package versions.

.DESCRIPTION
    Displays the contents of the package version cache, showing:
    - Cached package names and versions
    - Cache age and statistics
    - Comparison with current package versions (optional)
    - Cache health and status

.PARAMETER Source
    Filter by package source (Store, Winget, or Chocolatey).

.PARAMETER PackageName
    Filter by specific package name.

.PARAMETER ShowComparison
    Compare cached versions with current versions from package managers.

.PARAMETER ClearCache
    Clear the entire cache or specific source.

.PARAMETER Statistics
    Show only cache statistics without package details.

.EXAMPLE
    .\view-cache.ps1
    Display all cached packages.

.EXAMPLE
    .\view-cache.ps1 -Source Winget
    Display only Winget cached packages.

.EXAMPLE
    .\view-cache.ps1 -ShowComparison
    Compare cached versions with current available versions.

.EXAMPLE
    .\view-cache.ps1 -ClearCache -Source Chocolatey
    Clear only Chocolatey cache.

.EXAMPLE
    .\view-cache.ps1 -Statistics
    Show cache statistics only.

.NOTES
    File Name      : view-cache.ps1
    Author         : Sathyendra Vemulapalli
    Prerequisite   : PowerShell 5.1 or later
#>

[CmdletBinding()]
param(
    [ValidateSet("Store", "Winget", "Chocolatey")]
    [string]$Source,
    
    [string]$PackageName,
    
    [switch]$ShowComparison,
    
    [switch]$ClearCache,
    
    [switch]$Statistics
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

# Load configuration
$config = Get-UpdateConfig -ConfigPath "$PSScriptRoot\config.json"
$cachePath = if ($config -and $config.DifferentialUpdates.CachePath) { 
    Join-Path $PSScriptRoot $config.DifferentialUpdates.CachePath.TrimStart(".\")
} else { 
    "$PSScriptRoot\cache\package-cache.json" 
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  Package Cache Viewer" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

# Handle cache clearing
if ($ClearCache) {
    Write-Host "`nClearing package cache..." -ForegroundColor Yellow
    
    $confirmMessage = if ($Source) {
        "Are you sure you want to clear the $Source cache? (Y/N)"
    } else {
        "Are you sure you want to clear the ENTIRE cache? (Y/N)"
    }
    
    $confirm = Read-Host $confirmMessage
    
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        $success = if ($Source) {
            Clear-PackageCache -Source $Source -CachePath $cachePath
        } else {
            Clear-PackageCache -CachePath $cachePath
        }
        
        if ($success) {
            Write-Host "Cache cleared successfully!" -ForegroundColor Green
        } else {
            Write-Host "Failed to clear cache" -ForegroundColor Red
        }
    } else {
        Write-Host "Cache clear cancelled" -ForegroundColor Yellow
    }
    
    exit 0
}

# Get cache statistics
$stats = Get-CacheStatistics -CachePath $cachePath

if (-not $stats.Exists) {
    Write-Host "`nCache not initialized or not found." -ForegroundColor Yellow
    Write-Host "Run an update checker script to initialize the cache." -ForegroundColor Gray
    exit 0
}

# Display statistics
Write-Host "`nCache Statistics:" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Gray
Write-Host "Cache Location: $cachePath" -ForegroundColor White
Write-Host "Last Updated: $($stats.LastUpdated)" -ForegroundColor White
Write-Host "Cache Age: $($stats.AgeInHours) hours ($($stats.AgeInDays) days)" -ForegroundColor White
Write-Host "`nPackages Cached:" -ForegroundColor Cyan
Write-Host "  Store: $($stats.StorePackages) packages" -ForegroundColor White
Write-Host "  Winget: $($stats.WingetPackages) packages" -ForegroundColor White
Write-Host "  Chocolatey: $($stats.ChocolateyPackages) packages" -ForegroundColor White
Write-Host "  Total: $($stats.TotalPackages) packages" -ForegroundColor Green

# Exit if only statistics requested
if ($Statistics) {
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    exit 0
}

# Get cache contents
$cache = Get-PackageCache -CachePath $cachePath

if (-not $cache) {
    Write-Host "`nError loading cache contents" -ForegroundColor Red
    exit 1
}

# Determine which sources to display
$sourcesToShow = if ($Source) {
    @($Source)
} else {
    @("Store", "Winget", "Chocolatey")
}

# Display cached packages
foreach ($sourceType in $sourcesToShow) {
    $packages = $cache.Packages.$sourceType
    
    if ($PackageName) {
        $packages = $packages | Where-Object { $_.Name -like "*$PackageName*" }
    }
    
    if ($packages.Count -eq 0) {
        if (-not $Source -or $Source -eq $sourceType) {
            Write-Host "`n$sourceType Packages: None cached" -ForegroundColor Gray
        }
        continue
    }
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host "$sourceType Packages ($($packages.Count)):" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    # Convert to array for proper handling
    $packagesArray = @($packages)
    
    if ($ShowComparison) {
        # Show with current version comparison
        Write-Host "Note: Comparison with current versions requires running update check" -ForegroundColor Yellow
        
        $packagesArray | Sort-Object Name | Format-Table -AutoSize `
            @{Label="Package"; Expression={$_.Name}; Width=40},
            @{Label="Cached Version"; Expression={$_.Version}; Width=20},
            @{Label="Last Updated"; Expression={$_.LastUpdated}; Width=20}
    } else {
        # Show cached versions only
        $packagesArray | Sort-Object Name | Format-Table -AutoSize `
            @{Label="Package"; Expression={$_.Name}; Width=50},
            @{Label="Version"; Expression={$_.Version}; Width=15},
            @{Label="Last Updated"; Expression={$_.LastUpdated}; Width=20}
    }
}

# Cache health warnings
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "Cache Health:" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Gray

$cacheExpiryHours = if ($config -and $config.DifferentialUpdates.CacheExpiryHours) {
    $config.DifferentialUpdates.CacheExpiryHours
} else {
    24
}

if ($stats.AgeInHours -gt $cacheExpiryHours) {
    Write-Host "WARNING: Cache is older than $cacheExpiryHours hours" -ForegroundColor Yellow
    Write-Host "Consider running an update check to refresh the cache" -ForegroundColor Yellow
} else {
    $hoursUntilExpiry = $cacheExpiryHours - $stats.AgeInHours
    Write-Host "Cache is current (expires in $([math]::Round($hoursUntilExpiry, 1)) hours)" -ForegroundColor Green
}

# Show cache management tips
Write-Host "`nCache Management:" -ForegroundColor Cyan
Write-Host "  Clear all cache: .\view-cache.ps1 -ClearCache" -ForegroundColor Gray
Write-Host "  Clear specific source: .\view-cache.ps1 -ClearCache -Source Winget" -ForegroundColor Gray
Write-Host "  Refresh cache: Run .\update-checker1.ps1 or .\update-checker2.ps1" -ForegroundColor Gray

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
