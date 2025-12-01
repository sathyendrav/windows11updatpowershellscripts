<#
.SYNOPSIS
    Test script for Windows Toast Notifications.

.DESCRIPTION
    This script demonstrates and tests the toast notification functionality
    by sending sample notifications of different types.

.PARAMETER DelaySeconds
    Delay in seconds between each test notification (default: 3).

.PARAMETER SkipConfigTest
    Skip the config-based notification test (Test 5).

.NOTES
    File Name      : test-notifications.ps1
    Author         : Sathyendra Vemulapalli
    Prerequisite   : Windows 10/11, PowerShell 5.1+
    
.EXAMPLE
    .\test-notifications.ps1
    Tests all notification types with 3-second delays between each.

.EXAMPLE
    .\test-notifications.ps1 -DelaySeconds 5
    Tests notifications with 5-second delays.

.EXAMPLE
    .\test-notifications.ps1 -SkipConfigTest
    Tests only the basic notification types, skipping config test.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Delay in seconds between each test notification")]
    [ValidateRange(1, 60)]
    [int]$DelaySeconds = 3,
    
    [Parameter(HelpMessage = "Skip the config-based notification test")]
    [switch]$SkipConfigTest
)

# Import utility module
Import-Module "$PSScriptRoot\UpdateUtilities.psm1" -Force

Write-Host "Testing Windows Toast Notifications..." -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Test 1: Info notification
Write-Host "`n[1/5] Testing Info notification..." -ForegroundColor Yellow
Send-ToastNotification -Title "Update Check Started" -Message "Scanning for available updates..." -Icon Info
Start-Sleep -Seconds $DelaySeconds

# Test 2: Success notification
Write-Host "[2/5] Testing Success notification..." -ForegroundColor Yellow
Send-ToastNotification -Title "Updates Complete" -Message "15 packages updated successfully" -Icon Success
Start-Sleep -Seconds $DelaySeconds

# Test 3: Warning notification
Write-Host "[3/5] Testing Warning notification..." -ForegroundColor Yellow
Send-ToastNotification -Title "Updates Available" -Message "5 packages can be updated" -Icon Warning
Start-Sleep -Seconds $DelaySeconds

# Test 4: Error notification
Write-Host "[4/5] Testing Error notification..." -ForegroundColor Yellow
Send-ToastNotification -Title "Update Failed" -Message "Some updates could not be installed. Check logs for details." -Icon Error
Start-Sleep -Seconds $DelaySeconds

# Test 5: Using the helper function with config
if (-not $SkipConfigTest) {
    Write-Host "[5/5] Testing Send-UpdateNotification with config..." -ForegroundColor Yellow

    # Create test config
    $testConfig = @{
        Notifications = @{
            EnableToastNotifications = $true
        }
    }

    Send-UpdateNotification -Type "Complete" -Details "Test completed successfully" -Config $testConfig
} else {
    Write-Host "[5/5] Config-based notification test skipped." -ForegroundColor Gray
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "Toast notification test completed!" -ForegroundColor Green
Write-Host "Check your Windows Action Center if you didn't see the notifications." -ForegroundColor Yellow
